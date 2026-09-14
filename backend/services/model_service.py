from __future__ import annotations

import pickle
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import Orange.data
import Orange.base

from schemas.domain_schema import DomainResponse, VariableInfo


class ModelNotLoadedError(RuntimeError):
    pass


@dataclass(frozen=True)
class OneHotGroup:
    """A set of indicator columns that together encode one discrete variable.

    Orange's ``Continuize`` preprocessor rewrites ``nausea`` into the columns
    ``nausea=No`` and ``nausea=Yes``; this records ``base="nausea"``,
    ``values=["No", "Yes"]`` and the matching column names.
    """

    base: str
    values: tuple[str, ...]
    columns: tuple[str, ...]

    def value_of(self, column: str) -> str:
        return self.values[self.columns.index(column)]


class ModelService:
    def __init__(self) -> None:
        self._model: Optional[Orange.base.Model] = None
        self._path: Optional[str] = None

    # ── loading ────────────────────────────────────────────────────────────────

    def load(self, path: str) -> None:
        resolved = Path(path).resolve()
        if not resolved.exists():
            raise FileNotFoundError(f"Model file not found: {path}")
        with open(resolved, "rb") as fh:
            obj = pickle.load(fh)
        if not callable(obj):
            raise ValueError("File does not contain a callable Orange model.")
        self._model = obj
        self._path = str(resolved)

    def is_loaded(self) -> bool:
        return self._model is not None

    @property
    def path(self) -> Optional[str]:
        return self._path

    @property
    def model_type(self) -> Optional[str]:
        """Class name of the loaded classifier, e.g. ``TreeModel``."""
        return type(self._model).__name__ if self._model is not None else None

    # ── domain introspection ───────────────────────────────────────────────────

    def _input_domain(self) -> Orange.data.Domain:
        """The domain the user is expected to supply values for.

        Learners such as Logistic Regression and Random Forest run a
        ``Continuize`` preprocessor before fitting, so ``model.domain`` holds
        one-hot columns (``nausea=No``, ``nausea=Yes``) rather than the
        discrete variables the model was trained from. Orange keeps the
        pre-preprocessing domain on ``model.original_domain``, and feeding the
        model a table in that domain lets it apply its own transformation.
        Models without a preprocessing step have the two domains identical.
        """
        model = self._model
        original = getattr(model, "original_domain", None)
        if original is not None and len(original.attributes) > 0:
            return original
        return model.domain  # type: ignore[union-attr]

    @staticmethod
    def _detect_one_hot_groups(
        attributes: tuple[Orange.data.Variable, ...],
    ) -> dict[str, OneHotGroup]:
        """Map indicator column name → its group, for ``base=value`` columns.

        This catches models trained on data that was *already* continuized
        before it reached the learner, where ``original_domain`` cannot undo
        the encoding. A lone ``x=y`` column is left alone: with only one
        indicator the remaining level has no name to show the user, and a
        continuous variable that merely has ``=`` in its name must keep
        working as a plain number.
        """
        candidates: dict[str, list[tuple[str, str]]] = {}
        for var in attributes:
            if not isinstance(var, Orange.data.ContinuousVariable):
                continue
            base, sep, value = var.name.partition("=")
            if not sep or not base or not value:
                continue
            candidates.setdefault(base, []).append((var.name, value))

        taken = {var.name for var in attributes}
        groups: dict[str, OneHotGroup] = {}
        for base, members in candidates.items():
            # `base in taken` means a real column already owns that name.
            if len(members) < 2 or base in taken:
                continue
            group = OneHotGroup(
                base=base,
                values=tuple(value for _, value in members),
                columns=tuple(column for column, _ in members),
            )
            for column, _ in members:
                groups[column] = group
        return groups

    def get_domain_response(self) -> DomainResponse:
        self._require_loaded()
        domain = self._input_domain()
        groups = self._detect_one_hot_groups(domain.attributes)

        features: list[VariableInfo] = []
        seen_groups: set[str] = set()
        for var in domain.attributes:
            group = groups.get(var.name)
            if group is None:
                features.append(self._var_to_info(var, "feature"))
            elif group.base not in seen_groups:
                # Collapse the whole indicator block into one discrete field.
                seen_groups.add(group.base)
                features.append(
                    VariableInfo(
                        name=group.base,
                        type="discrete",
                        role="feature",
                        values=list(group.values),
                    )
                )

        # The class variable is read from the fitted domain: predictions are
        # indexed against that one.
        class_info = self._var_to_info(
            self._model.domain.class_var, "class"  # type: ignore[union-attr]
        )
        return DomainResponse(
            features=features,
            class_var=class_info,
            model_type=self.model_type,
        )

    @staticmethod
    def _var_to_info(var: Orange.data.Variable, role: str) -> VariableInfo:
        if isinstance(var, Orange.data.ContinuousVariable):
            attrs = var.attributes or {}
            lo = attrs.get("min")
            hi = attrs.get("max")
            return VariableInfo(
                name=var.name,
                type="continuous",
                role=role,
                min=float(lo) if lo is not None else None,
                max=float(hi) if hi is not None else None,
            )
        if isinstance(var, Orange.data.DiscreteVariable):
            return VariableInfo(
                name=var.name,
                type="discrete",
                role=role,
                values=list(var.values),
            )
        if isinstance(var, Orange.data.TimeVariable):
            return VariableInfo(name=var.name, type="time", role=role)
        # StringVariable and any future types
        return VariableInfo(name=var.name, type="string", role=role)

    # ── prediction ─────────────────────────────────────────────────────────────

    def predict(
        self,
        values: dict[str, Any],
        missing_token: str = "?",
    ) -> tuple[str, dict[str, float]]:
        self._require_loaded()
        domain = self._input_domain()
        groups = self._detect_one_hot_groups(domain.attributes)

        row = self._build_row(values, domain, groups, missing_token)
        # Use only the input attributes; the model handles domain conversion internally
        input_domain = Orange.data.Domain(domain.attributes)
        table = Orange.data.Table.from_list(input_domain, [row])

        value_arr, prob_arr = self._model(table, self._model.ValueProbs)  # type: ignore[union-attr]

        class_var = self._model.domain.class_var  # type: ignore[union-attr]
        predicted_class = class_var.values[int(value_arr[0])]
        prob_dict: dict[str, float] = {
            class_var.values[i]: float(prob_arr[0][i])
            for i in range(len(class_var.values))
        }
        return predicted_class, prob_dict

    @staticmethod
    def _build_row(
        values: dict[str, Any],
        domain: Orange.data.Domain,
        groups: dict[str, OneHotGroup],
        missing_token: str,
    ) -> list:
        row: list = []
        for var in domain.attributes:
            group = groups.get(var.name)
            if group is not None and var.name not in values:
                # The client sends the collapsed name ("nausea"); re-expand it
                # across the indicator columns. Sending the raw column name
                # instead still works and falls through to the numeric branch.
                raw = values.get(group.base)
                if raw is None or raw == missing_token or str(raw) not in group.values:
                    row.append(None)
                else:
                    row.append(1.0 if str(raw) == group.value_of(var.name) else 0.0)
                continue

            raw = values.get(var.name)
            if raw is None or raw == missing_token:
                row.append(None)
            elif isinstance(var, Orange.data.DiscreteVariable):
                row.append(str(raw))
            elif isinstance(var, (Orange.data.ContinuousVariable, Orange.data.TimeVariable)):
                try:
                    row.append(float(raw))
                except (TypeError, ValueError):
                    row.append(None)
            else:
                row.append(str(raw))
        return row

    # ── helpers ────────────────────────────────────────────────────────────────

    def _require_loaded(self) -> None:
        if not self.is_loaded():
            raise ModelNotLoadedError("No model is currently loaded.")


# Module-level singleton shared by all routers
model_service = ModelService()
