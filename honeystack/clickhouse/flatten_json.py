import json

def flatten_top_level(obj):
    for k, v in obj.items():
        if isinstance(v, (dict, list)):
            obj[k] = json.dumps(v, separators=(',', ':'))
    return obj

with open('infer.json') as infile, open('infer_flat.json', 'w') as outfile:
    for line in infile:
        if line.strip() and not line.strip().startswith('//'):
            obj = json.loads(line)
            obj = flatten_top_level(obj)
            outfile.write(json.dumps(obj) + '\n')
