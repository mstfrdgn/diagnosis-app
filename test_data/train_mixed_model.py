"""Train a small classifier with both continuous and discrete features,
to exercise both branches of VariableField."""
import pickle
import numpy as np
from Orange.data import Domain, ContinuousVariable, DiscreteVariable, Table
from Orange.classification import TreeLearner

rng = np.random.default_rng(42)
n = 200

age = rng.normal(50, 12, n)
cholesterol = rng.normal(200, 30, n)
smoker = rng.integers(0, 2, n)  # 0=No, 1=Yes

risk_score = 0.03 * (age - 50) + 0.02 * (cholesterol - 200) + 1.5 * smoker + rng.normal(0, 1, n)
diagnosis = (risk_score > np.median(risk_score)).astype(int)

age_var = ContinuousVariable("age")
age_var.attributes["min"] = 0
age_var.attributes["max"] = 120
cholesterol_var = ContinuousVariable("cholesterol")
cholesterol_var.attributes["min"] = 100
cholesterol_var.attributes["max"] = 400
smoker_var = DiscreteVariable("smoker", values=("No", "Yes"))
diagnosis_var = DiscreteVariable("diagnosis", values=("Negative", "Positive"))

domain = Domain([age_var, cholesterol_var, smoker_var], class_vars=diagnosis_var)
X = np.column_stack([age, cholesterol, smoker])
Y = diagnosis
table = Table.from_numpy(domain, X, Y)

learner = TreeLearner()
model = learner(table)

with open("heart_risk_model.pkcls", "wb") as fh:
    pickle.dump(model, fh)

print("Saved: heart_risk_model.pkcls")
print("Domain attributes:", [(v.name, type(v).__name__) for v in model.domain.attributes])
print("Class var:", model.domain.class_var.name, model.domain.class_var.values)
