"""Chequeos locales de estructura y contrato. No sustituyen cfn-lint ni AWS."""
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
class Loader(yaml.SafeLoader):
    pass

def intrinsic(loader, suffix, node):
    if isinstance(node, yaml.ScalarNode): value = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode): value = loader.construct_sequence(node)
    else: value = loader.construct_mapping(node)
    key = suffix if suffix in {"Ref", "Condition"} else "Fn::" + suffix
    if suffix == "GetAtt" and isinstance(value, str): value = value.split(".", 1)
    return {key: value}
Loader.add_multi_constructor("!", intrinsic)

def load(path):
    with path.open(encoding="utf-8") as stream:
        return yaml.load(stream, Loader=Loader)

def walk(value):
    yield value
    if isinstance(value, dict):
        for v in value.values(): yield from walk(v)
    elif isinstance(value, list):
        for v in value: yield from walk(v)

root = load(ROOT / "main.yaml")
assert len(root["Resources"]) == 3
for name, stack in root["Resources"].items():
    assert stack["Type"] == "AWS::CloudFormation::Stack"
    child = load(ROOT / stack["Properties"]["TemplateURL"])
    assert set(stack["Properties"].get("Parameters", {})) == set(child.get("Parameters", {})), name
    for item in walk(root):
        if isinstance(item, dict) and "Fn::GetAtt" in item:
            resource, attr = item["Fn::GetAtt"]
            if resource == name and attr.startswith("Outputs."):
                assert attr[8:] in child.get("Outputs", {}), attr
for path in [ROOT / "bootstrap.yaml", ROOT / "main.yaml", *sorted((ROOT / "templates").glob("*.yaml"))]:
    template = load(path)
    assert template["Description"]
    assert len(template["Description"].encode()) <= 1024
    assert path.stat().st_size <= 51200
    for name, resource in template["Resources"].items():
        props = resource.get("Properties", {})
        if resource["Type"] == "AWS::EC2::Instance":
            assert props["MetadataOptions"]["HttpTokens"] == "required"
            assert all(d["Ebs"]["Encrypted"] for d in props["BlockDeviceMappings"])
            if name in {"Backend", "PruebaIntegranteA"}:
                interface = props["NetworkInterfaces"][0]
                assert interface["AssociatePublicIpAddress"] is False
                assert interface["SubnetId"] in ({"Ref": "PrivateSubnetId"},)
        if resource["Type"] == "AWS::S3::Bucket":
            assert all(props["PublicAccessBlockConfiguration"].values())
            assert props["BucketEncryption"]
            assert resource["DeletionPolicy"] == "Retain"
    print("OK:", path.relative_to(ROOT))
print("Contratos hijos/parametros/salidas y controles basicos correctos.")
