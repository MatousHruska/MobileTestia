# Project Name: Heroes of Tesia
**Type:** Mobile Action RPG
**Art Style:** Pixel Art (32x32px base), Top-Down 3/4 Perspective
**Orientation:** Landscape (Horizontal)

---

## 1. Core Visual & Technical Settings
- **Resolution:** Pixel Perfect implementation required.
- **PPU (Pixels Per Unit):** 32 (Standardize 32 pixels = 1 world unit).
- **Camera:** Orthographic.
- **Perspective:** 3/4 Top-Down.
    - Z-axis does NOT affect physics.
    - Z-axis is used ONLY for sorting layers.
- **Sorting:** Y-Axis Transparency Sorting (objects lower on screen render in front of objects higher on screen).

---

## 2. Character Visual Architecture ("Paper Doll" System)
**Constraint:** Strict Asset Limitations to optimize production.
- **Body:** Only ONE "Body" animation set exists (Idle, Walk, Attack, Die, Hit).
- **Head/Helmet:** Separate sprite sheets layered *over* the body.
- **Weapon:** Separate sprite assets anchored to a "Hand" transform.
- **Synchronization:**
    - The `CharacterAnimator` drives the Body.
    - Head and Weapon sprites must listen to Body frame updates to sync positions (avoiding "floaty" gear).
    - **Z-Sorting Logic:** Weapon renders *behind* player when facing UP, and *in front* when facing DOWN/SIDE.

---

## 3. Controls & Input (Mobile)
- **Left Screen:** Virtual Analog Joystick (Floating or Fixed anchor).
- **Right Screen:**
    - Large Action Button (Attack).
    - Smaller Action Button (Dodge).
    - Skill/Ability buttons arranged in an arc or grid.
- **Input Logic:** Movement Vector must be normalized (Magnitude never > 1).

---

## 4. Player Movement Logic
- **Input:** 8-Directional (Up, Down, Left, Right, + 4 Diagonals).
- **Physics:** Rigidbody2D movement.
- **Smoothing:** Apply slight acceleration/deceleration (Easing) to velocity. Do not start/stop instantly.
- **Animation Mapping (8-Way Move / 4-Way Animate):**
    - The character only has 4 Cardinal Animations (Up, Down, Left, Right).
    - **Diagonal Logic:** If Input is Diagonal (e.g., Up-Right), prioritize Horizontal axis for animation selection.
    - **Sprite Flipping:** If moving Left, use Right animation and flip sprite X.

---

## 5. Combat Mechanics
- **Attack Direction:** Strictly 4-Cardinal (Up, Down, Left, Right).
- **Snap Logic:** When attacking, snap the character's facing direction to the nearest Cardinal direction based on Joystick input.
- **Lunge:** On attack start, apply a short, impulse force (Lunge) in the facing direction.
- **Hitboxes:** Melee hitboxes appear offset in the direction of the attack.

---

## 6. Camera Behavior
- **Target:** Follows Player.
- **Look-Ahead:** The camera should offset slightly in the direction of the player's movement velocity (not centered perfectly).
- **Damping:** Smooth return to center when player stops.

---

## 7. UI Layout (HUD)
- **Top-Left:** Player Frame (Health Bar, Mana Bar, Stamina Bar).
- **Top-Right:** Hamburger Menu (Pause/Inventory/Settings).
- **Right-Bottom:** Action Buttons (Attack/Dodge/Skills).
- **Left-Bottom:** Joystick area.

---

## 8. RPG Progression Systems (Diablo-Lite)
**Attributes:**
- **Strength (STR):** Phys Dmg.
- **Dexterity (DEX):** Atk Speed, Crit Chance.
- **Intelligence (INT):** Magic Dmg, Mana Pool/Regen.
- **Endurance (END):** Health Pool/Regen.
- **Luck (LUK):** Drop Rates, Gold Find, Crit Dmg.

**Leveling Loop:**
1. Gain XP -> Level Up -> Visual FX + Full Heal.
2. **Rewards:** +5 Stat Points (Player assigned), +1 Talent Point.

**Talent Tree:**
- UI: Scrollable tree view.
- Nodes: Passive (Stat Multipliers) and Active (Unlock Spells).

---

## 9. Inventory & Equipment
**Data Structure:** Database (ID, Name, Icon, Type, Rarity, StatModifiers).
**Slots:**
- **Head:** (Visual change - Sprite Swap).
- **Body:** (Stats only).
- **Hands:** (Stats only).
- **Boots:** (Stats only).
- **Main Hand:** (Weapon - Visual change - Sprite Swap).
- **Ring & Amulet:** (Stats only).
- **Quick Slot:** (Consumable item for quick use).
**Backpack:** Grid-based (e.g., 20 slots). Drag-and-drop or Tap-to-Equip.

---

## 10. World Architecture
**Scene Management:**
- **Zone:** Self-contained scene (Town, Forest).
- **Portals:** Trigger load next scene -> Spawn Player at specific `SpawnID`.
- **Persistence:**
    - **Global:** Quest progress, Inventory, Stats (Saved to disk).
    - **Local:** Dropped loot/enemies reset on Zone unload (unless "One-Time" boss).

**Spawning:**
- **Enemies:** Spawn on Trigger (Zone Enter or Region Enter).
- **Loot Tables:** Standard (Weighted Random), Miniboss (Rare Table), Boss (Fixed + Story).

**Quests:**
- States: NotStarted -> InProgress -> Completed -> TurnedIn.
- Indicators: "!" and "?" above NPCs.

**Save/Load:**
- Trigger: Auto-save on Zone Change, Level Up, Manual Save.
- Data: JSON format for easy debugging during dev.
