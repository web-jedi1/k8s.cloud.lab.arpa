from json import load

with open("../terraform/tf_outputs.json") as f:
    tf_outputs = load(f)

masters = tf_outputs["k8s_master_private_ips"]["value"]
workers = tf_outputs["k8s_worker_private_ips"]["value"]

GROUPS = {
    "masters": masters,
    "workers": workers,
    "all": masters + workers,
}
