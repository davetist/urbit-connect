"""Validate OpenAPI and positive/negative protocol fixtures."""
import json
from pathlib import Path
from openapi_spec_validator import validate
from jsonschema import Draft202012Validator
ROOT=Path(__file__).resolve().parents[1]
def main():
    spec=json.loads((ROOT/'protocol/v1/openapi.yaml').read_text());validate(spec)
    cases={'create':'Mutation','update':'Mutation','delete':'Mutation','snapshot':'SnapshotPage','snapshot-last':'SnapshotPage','conflict':'Error','scope-denied':'Error','revoked':'Error','stale-cursor':'Error'}
    count=0
    for name,schema in cases.items():
        validator=Draft202012Validator({'$ref':'#/components/schemas/'+schema,'components':spec['components']})
        value=json.loads((ROOT/f'protocol/v1/fixtures/{name}.json').read_text());validator.validate(value);count+=1
    negative=json.loads((ROOT/'protocol/v1/fixtures/namespace-override.json').read_text())
    validator=Draft202012Validator({'$ref':'#/components/schemas/Mutation','components':spec['components']})
    if validator.is_valid(negative):raise AssertionError('Namespace override fixture was accepted')
    count+=1
    validator=Draft202012Validator({'$ref':'#/components/schemas/ClientUpdate','components':spec['components']})
    for value in [{'name':'Renamed'},{'enabled':False}]:validator.validate(value);count+=1
    for value in [{},{'enabled':False,'redirectURI':'org.example.other:/callback'}]:
        if validator.is_valid(value):raise AssertionError('Invalid partial client update accepted')
        count+=1
    print(f'PASS: OpenAPI {spec["openapi"]}, {len(spec["paths"])} routes, {count} schema fixtures')
if __name__=='__main__':main()
