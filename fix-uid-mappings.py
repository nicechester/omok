#!/usr/bin/env python3
"""
Fix uidMappings by scanning all games and adding missing Firebase UIDs.

For each player in games, if they have a deviceUID in uidMappings but their
game player key (Firebase UID) isn't in the mapping, add it.
"""

import json
import sys
from collections import defaultdict

INPUT_FILE = sys.argv[1] if len(sys.argv) > 1 else '~/Downloads/omok-original-no-audio.json'
INPUT_FILE = INPUT_FILE.replace('~', '/Users/chester.kim')
OUTPUT_FILE = INPUT_FILE.replace('.json', '-fixed.json')

with open(INPUT_FILE) as f:
    data = json.load(f)

games = data.get('omok', {}).get('games', {})
uid_mappings = data.get('omok', {}).get('uidMappings', {})

# Build reverse map: Firebase UID -> device UID
firebase_to_device = {}
for device_uid, mapping in uid_mappings.items():
    for firebase_uid in mapping.get('firebaseUids', []):
        firebase_to_device[firebase_uid] = device_uid

# Collect all Firebase UIDs per player name (heuristic: same name = same person)
name_to_firebase_uids = defaultdict(set)
for game_id, game in games.items():
    players = game.get('players', {})
    for uid, pdata in players.items():
        name = pdata.get('name')
        if name and uid != 'ai-player':
            name_to_firebase_uids[name].add(uid)

print("Players and their Firebase UIDs:")
for name, uids in sorted(name_to_firebase_uids.items()):
    print(f"  {name}: {uids}")

# For each name, find if any UID maps to a device UID, then add all others
fixes_made = 0
for name, firebase_uids in name_to_firebase_uids.items():
    # Find device UID for this player (if any Firebase UID is mapped)
    device_uid = None
    for fuid in firebase_uids:
        if fuid in firebase_to_device:
            device_uid = firebase_to_device[fuid]
            break
    
    if not device_uid:
        # Check if any of the UIDs IS a device UID (already migrated or new user)
        for fuid in firebase_uids:
            if fuid in uid_mappings:
                device_uid = fuid
                break
    
    if not device_uid:
        print(f"  WARNING: No device UID found for {name}, skipping")
        continue
    
    # Ensure all Firebase UIDs are in the mapping
    current_mapped = set(uid_mappings.get(device_uid, {}).get('firebaseUids', []))
    missing = firebase_uids - current_mapped - {device_uid}  # Don't add device UID to its own list
    
    if missing:
        print(f"\n  Fixing {name} (device: {device_uid}):")
        print(f"    Adding: {missing}")
        if device_uid not in uid_mappings:
            uid_mappings[device_uid] = {'firebaseUids': []}
        uid_mappings[device_uid]['firebaseUids'].extend(missing)
        fixes_made += len(missing)

# Update data
data['omok']['uidMappings'] = uid_mappings

with open(OUTPUT_FILE, 'w') as f:
    json.dump(data, f)

print(f"\nFixes made: {fixes_made}")
print(f"Saved to: {OUTPUT_FILE}")
