#!/usr/bin/env python3
"""Script to remove the stray VLCRenderer.swift line from project.pbxproj"""

file_path = r'c:\Users\nihad\Desktop\Work\VS Code projects\Luna\Luna.xcodeproj\project.pbxproj'
target_line = '1A1A1A1A1A1A1A1A1A1A1A1A /* VLCRenderer.swift in Sources */,'

try:
    # Read the file
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Check if target line exists
    if target_line in content:
        lines = content.split('\n')
        filtered_lines = [line for line in lines if target_line not in line]
        
        # Write back to file
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(filtered_lines))
        
        print(f'Success: Line containing "{target_line}" has been removed.')
        print(f'Original line count: {len(lines)}')
        print(f'New line count: {len(filtered_lines)}')
    else:
        print('Error: Target line not found in the file.')
        
except Exception as e:
    print(f'Error: {str(e)}')
