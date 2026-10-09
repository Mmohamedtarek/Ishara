"""Pretty-prints library.json with one frame per line (readable diffs)."""
import json, sys
def dump(lib):
    out = ['{']
    keys = [k for k in lib if k not in ('shapes', 'signs')]
    for k in keys:
        out.append(f'  {json.dumps(k)}: {json.dumps(lib[k], ensure_ascii=False)},')
    out.append('  "shapes": {')
    sh = list(lib['shapes'].items())
    for i, (k, v) in enumerate(sh):
        out.append(f'    {json.dumps(k)}: {json.dumps(v)}' + (',' if i < len(sh) - 1 else ''))
    out.append('  },')
    out.append('  "signs": {')
    sg = list(lib['signs'].items())
    for i, (k, v) in enumerate(sg):
        extra = {kk: vv for kk, vv in v.items() if kk != 'frames'}
        head = ''.join(f'{json.dumps(kk)}: {json.dumps(vv, ensure_ascii=False)}, ' for kk, vv in extra.items())
        out.append(f'    {json.dumps(k)}: {{{head}"frames": [')
        fr = v['frames']
        for j, f in enumerate(fr):
            out.append('      ' + json.dumps(f) + (',' if j < len(fr) - 1 else ''))
        out.append('    ]}' + (',' if i < len(sg) - 1 else ''))
    out.append('  }')
    out.append('}')
    return '\n'.join(out) + '\n'
if __name__ == '__main__':
    p = sys.argv[1]
    lib = json.load(open(p, encoding='utf-8'))
    open(p, 'w', encoding='utf-8').write(dump(lib))
