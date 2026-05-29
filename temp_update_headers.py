from pathlib import Path

root = Path('categories')
updated = 0
for path in root.rglob('*.sql'):
    text = path.read_text(encoding='utf-8')
    if 'SAFE:ReadOnly' in text and 'SET NOCOUNT ON;' in text and 'Script Name :' in text:
        continue

    lines = text.splitlines()
    header_end = 0
    if lines and lines[0].strip().startswith('/*'):
        i = 0
        while i < len(lines) and not lines[i].strip().endswith('*/'):
            i += 1
        if i < len(lines) and lines[i].strip().endswith('*/'):
            header_end = i + 1

    name = path.stem
    category = path.parts[-3] if len(path.parts) >= 3 else 'general'
    purpose = 'Operational DBA review script.'
    if 'Wait' in name or 'LongRunning' in name:
        purpose = 'Review current wait or session activity for performance triage.'
    elif 'Backup' in name or 'Restore' in name:
        purpose = 'Review backup and restore readiness for operational checks.'
    elif 'DatabaseHealth' in name or 'Integrity' in name or 'Tempdb' in name:
        purpose = 'Review database health and maintenance posture.'
    elif 'Disk' in name or 'Sizes' in name or 'Growth' in name or 'Log' in name:
        purpose = 'Review storage consumption and growth risk.'
    elif 'Agent' in name or 'Memory' in name or 'Version' in name or 'Cpu' in name:
        purpose = 'Review instance configuration or environment state.'

    if 'Script Name :' not in text:
        header = [
            '/*',
            f'Script Name : {name}',
            f'Category    : {category}',
            f'Purpose     : {purpose}',
            'Author      : Peter Whyte (https://sqldba.blog)',
            'Safe        : Read-only',
            'Impact      : Low',
            'Requires    : VIEW DATABASE STATE / VIEW SERVER STATE as applicable',
            '*/',
            ''
        ]
        text = '\n'.join(header) + '\n' + text
        lines = text.splitlines()
        header_end = len(header)
    else:
        if 'SAFE:ReadOnly' not in text:
            if header_end > 0:
                lines = lines[:header_end] + [''] + ['-- SAFE:ReadOnly', '-- IMPACT:Low'] + [''] + lines[header_end:]
                text = '\n'.join(lines)
            else:
                text = '-- SAFE:ReadOnly\n-- IMPACT:Low\n' + text

    if 'SET NOCOUNT ON;' not in text:
        if header_end > 0:
            lines = text.splitlines()
            insert_at = header_end + 1
            lines = lines[:insert_at] + ['SET NOCOUNT ON;'] + lines[insert_at:]
            text = '\n'.join(lines)
        else:
            text = 'SET NOCOUNT ON;\n\n' + text

    path.write_text(text, encoding='utf-8')
    updated += 1

print(f'Updated {updated} SQL files with metadata, safety markers, and SET NOCOUNT where needed.')
