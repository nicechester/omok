#!/usr/bin/env python3
"""
Migrate game player seats from Firebase UIDs to device UIDs.

Usage:
  python migrate-to-device-uid.py ~/Downloads/omok-5-in-a-row-default-rtdb-export.json

Output:
  Writes migrated JSON to omok-migrated.json
"""

import json
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: python migrate-to-device-uid.py <path-to-export.json>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    with open(input_path, 'r') as f:
        data = json.load(f)

    games = data.get('omok', {}).get('games', {})
    uid_mappings = data.get('omok', {}).get('uidMappings', {})

    # Build reverse mapping: Firebase UID -> Device UID
    firebase_to_device = {}
    for device_uid, mapping in uid_mappings.items():
        for firebase_uid in mapping.get('firebaseUids', []):
            firebase_to_device[firebase_uid] = device_uid

    print("=== UID Mappings (Firebase -> Device) ===", file=sys.stderr)
    for fb, dev in firebase_to_device.items():
        print(f"  {fb} -> {dev}", file=sys.stderr)
    print("", file=sys.stderr)

    migrated_count = 0
    skipped_count = 0

    for game_id, game in games.items():
        if not game.get('players'):
            continue

        new_players = {}
        for player_uid, player_data in game['players'].items():
            # Skip AI player
            if player_uid == 'ai-player':
                new_players[player_uid] = player_data
                continue

            # Check if this is a Firebase UID that should be migrated
            device_uid = firebase_to_device.get(player_uid)
            if device_uid:
                name = player_data.get('name', 'unnamed')
                print(f"[{game_id}] Migrating {player_uid} -> {device_uid} ({name})", file=sys.stderr)
                new_players[device_uid] = player_data
                migrated_count += 1
            else:
                # Already a device UID or unknown, keep as-is
                new_players[player_uid] = player_data
                skipped_count += 1

        # Update createdBy if it was migrated
        if game.get('createdBy') and game['createdBy'] in firebase_to_device:
            old = game['createdBy']
            game['createdBy'] = firebase_to_device[old]
            print(f"[{game_id}] Migrating createdBy {old} -> {game['createdBy']}", file=sys.stderr)

        # Update scores keys if they were migrated
        if game.get('scores'):
            new_scores = {}
            for uid, score in game['scores'].items():
                device_uid = firebase_to_device.get(uid)
                new_scores[device_uid if device_uid else uid] = score
            game['scores'] = new_scores

        game['players'] = new_players

    print("", file=sys.stderr)
    print(f"=== Summary ===", file=sys.stderr)
    print(f"Migrated: {migrated_count} player seats", file=sys.stderr)
    print(f"Skipped: {skipped_count} (already device UID or AI)", file=sys.stderr)

    # Write migrated data
    output_path = "omok-migrated.json"
    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Written to: {output_path}", file=sys.stderr)

if __name__ == '__main__':
    main()
