"""Train a classifier with a learner that continuizes its input, so the fitted
model's domain holds one-hot columns ("nausea=No", "nausea=Yes") instead of the
discrete variables. Logistic Regression and Random Forest both do this; the
backend has to present the original discrete fields regardless."""
import pickle
import numpy as np
from Orange.data import Domain, ContinuousVariable, DiscreteVariable, Table
from Orange.classification import LogisticRegressionLearner

rng = np.random.default_rng(7)
n = 300

temperature = rng.normal(37.5, 1.1, n)
nausea = rng.integers(0, 2, n)          # 0=No, 1=Yes
pain = rng.integers(0, 3, n)            # 0=None, 1=Mild, 2=Severe

score = 0.8 * (temperature - 37.5) + 1.3 * nausea + 0.7 * pain + rng.normal(0, 1, n)
appendicitis = (score > np.median(score)).astype(int)

temperature_var = ContinuousVariable("temperature")
temperature_var.attributes["min"] = 35
temperature_var.attributes["max"] = 42
nausea_var = DiscreteVariable("nausea", values=("No", "Yes"))
pain_var = DiscreteVariable("pain", values=("None", "Mild", "Severe"))
diagnosis_var = DiscreteVariable("diagnosis", values=("Negative", "Positive"))

domain = Domain([temperature_var, nausea_var, pain_var], class_vars=diagnosis_var)
X = np.column_stack([temperature, nausea, pain])
table = Table.from_numpy(domain, X, appendicitis)

learner = LogisticRegressionLearner()
model = learner(table)

with open("onehot_model.pkcls", "wb") as fh:
    pickle.dump(model, fh)

print("Saved: onehot_model.pkcls")
print("Fitted domain:", [(v.name, type(v).__name__) for v in model.domain.attributes])
print("Original domain:", [(v.name, type(v).__name__) for v in model.original_domain.attributes])
print("Class var:", model.domain.class_var.name, model.domain.class_var.values)
