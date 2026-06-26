#!/bin/bash
#
# bump_version.sh — Bump the version and build number for all platforms
#
# In Flutter, the version for iOS, Android, macOS, Linux, and Windows 
# is fully controlled by the `version:` field in `pubspec.yaml`.
#
# Usage: 
#   ./scripts/bump_version.sh build  -> bumps 1.0.0+1 to 1.0.0+2
#   ./scripts/bump_version.sh patch  -> bumps 1.0.0+1 to 1.0.1+1
#   ./scripts/bump_version.sh minor  -> bumps 1.0.0+1 to 1.1.0+1
#   ./scripts/bump_version.sh major  -> bumps 1.0.0+1 to 2.0.0+1

set -e

BUMP_TYPE=$1

if [[ ! "$BUMP_TYPE" =~ ^(major|minor|patch|build)$ ]]; then
  echo "Usage: ./scripts/bump_version.sh [major|minor|patch|build]"
  exit 1
fi

python3 -c "
import sys, re

bump_type = sys.argv[1]
filepath = 'pubspec.yaml'

with open(filepath, 'r') as f:
    lines = f.readlines()

new_version_str = ''
for i, line in enumerate(lines):
    if line.startswith('version:'):
        # Match 'version: x.y.z+b'
        match = re.match(r'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', line)
        if match:
            major, minor, patch, build = map(int, match.groups())
            
            if bump_type == 'major':
                major += 1
                minor = 0
                patch = 0
                build = 1
            elif bump_type == 'minor':
                minor += 1
                patch = 0
                build = 1
            elif bump_type == 'patch':
                patch += 1
                build = 1
            elif bump_type == 'build':
                build += 1
            
            new_version_str = f'{major}.{minor}.{patch}+{build}'
            lines[i] = f'version: {new_version_str}\n'
            break

if new_version_str:
    with open(filepath, 'w') as f:
        f.writelines(lines)
    print(f'✅ Successfully bumped version to {new_version_str}')
    print('All platforms (iOS, Android, macOS, etc.) will automatically use this new version on the next build!')
else:
    print('❌ Failed to find a valid version string in pubspec.yaml')
    sys.exit(1)
" "$BUMP_TYPE"
