from __future__ import annotations

import pickle
from pathlib import Path
from typing import Any, Optional

import Orange.data
import Orange.base

from schemas.domain_schema import DomainResponse, VariableInfo


class ModelNotLoadedError(RuntimeError):
    pass


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

    def get_domain_response(self) -> DomainResponse:
        self._require_loaded()
        domain = self._model.domain  # type: ignore[union-attr]
        features = [self._var_to_info(v, "feature") for v in domain.attributes]
        class_info = self._var_to_info(domain.class_var, "class")
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
        domain = self._model.domain  # type: ignore[union-attr]

        row = self._build_row(values, domain, missing_token)
        # Use only the input attributes; the model handles domain conversion internally
        input_domain = Orange.data.Domain(domain.attributes)
        table = Orange.data.Table.from_list(input_domain, [row])

        value_arr, prob_arr = self._model(table, self._model.ValueProbs)  # type: ignore[union-attr]

        class_var = domain.class_var
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
        missing_token: str,
    ) -> list:
        row: list = []
        for var in domain.attributes:
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
