"""Train a simple Orange classifier on the Iris dataset and pickle it,
mimicking what a user would export from Orange Canvas as a .pkcls file."""
import pickle
import Orange
from Orange.data import Table
from Orange.classification import LogisticRegressionLearner

data = Table("iris")
learner = LogisticRegressionLearner()
model = learner(data)

out_path = "iris_model.pkcls"
with open(out_path, "wb") as fh:
    pickle.dump(model, fh)

print("Saved:", out_path)
print("Domain attributes:", [(v.name, type(v).__name__) for v in model.domain.attributes])
print("Class var:", model.domain.class_var.name, model.domain.class_var.values)
