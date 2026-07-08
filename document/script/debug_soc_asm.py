"""Check soc_test_asm content."""
import sys, re
with open(r'E:\rvp_nexys\document\script\generate_all_hex.py', 'r', encoding='utf-8') as f:
    content = f.read()

m = re.search(r'soc_test_asm = """"(.*?)""""', content, re.DOTALL)
if not m:
    m = re.search(r'soc_test_asm = """(.*?)"""', content, re.DOTALL)

if m:
    src = m.group(1)
    lines = [l.strip() for l in src.split('\n') if l.strip() and not l.strip().startswith('#')]
    for i, l in enumerate(lines):
        print(f'  [{i:2d}] {l}')
    print(f'\nTotal: {len(lines)} instructions')
else:
    print('Not found')
    # Try alternate pattern
    m2 = re.search(r'Read Timer COUNT', content)
    if m2:
        print(f'Found "Read Timer COUNT" at position {m2.start()}')
        print(content[m2.start()-50:m2.end()+80])
