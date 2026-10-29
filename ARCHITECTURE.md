# Project PoE — Game Architecture & Structure

เอกสารสรุปโครงสร้างตัวเกม **Project PoE** (แนว 2.5D Isometric Top-down ARPG สไตล์ Anime / Cel-Shaded) สำหรับใช้อ้างอิงเวลาแก้ไขปรับปรุงระบบหรือเพิ่มฟีเจอร์ใหม่

---

## 0. สถานะ: เวอร์ชันแรก (MVP)

| ขอบเขต MVP | ทำแล้วที่ไหน |
|---|---|
| ตัวละคร 1 แบบ สกิลโจมตี 1-2 อย่าง | `SkillData`: **ฟัน** (`BasicSlash`) + **หมุนฟัน** (`SpinSlash`) / `CombatClient` + `CombatServer` |
| ศัตรู 1-2 ชนิด | `EnemyData`: **ภูตหิน** (`Grunt`) + บอส **ยักษ์หินผู้พิทักษ์** (`Brute`) / `EnemyService` |
| ไอเทมที่มี affix 2-3 แบบ | `ItemData`: ดาเมจ, เลือดสูงสุด (Prefix) + ความเร็วโจมตี (Suffix) / สุ่มใน `Loot` |
| อินเวนทอรีพื้นฐาน | `InventoryClient` (กด **I**) + `PlayerData` (เซิร์ฟเวอร์เป็นคนตัดสิน) |
| บันทึกข้อมูลผู้เล่น | `PlayerData`: DataStore เก็บเลเวล, EXP, กระเป๋า, ของที่สวมใส่ |
| ด่านเล็ก 1 ด่าน | `EnemyService`: ลูกสมุน 2 กลุ่ม + บอส ฆ่าบอส = "เคลียร์ด่าน!" (ตัวแมพต้องทำใน Studio ดูหัวข้อ 3) |

เพิ่มเติมนอกรายการ MVP ที่จำเป็นต่อการเล่นครบลูป: เลเวล/EXP, ผู้เล่นตายแล้วเกิดใหม่, แถบเลือดศัตรู, ปุ่มบนมือถือ

---

## 1. แผนผังโครงสร้างใน Roblox Studio (Explorer Hierarchy)

```text
📦 game (Project poe - placeId: 840433853)
 ┣ 📂 Workspace                        <-- [โลก 3D ในฉาก: แก้ใน Studio]
 ┃  ┣ 🧱 Baseplate / SpawnLocation     <-- พื้นแมพและจุดเกิด
 ┃  ┣ 📂 Enemies                       <-- มอนสเตอร์ทั้งหมด (EnemyService สร้างตอนเริ่มเกม)
 ┃  ┃  ┗ 🧍 TrainingDummy (Model)      <-- หุ่นซ้อมมือ R15 (HP: 500, ตายแล้วรีเลือดเอง, ไม่ให้ EXP/ของ)
 ┃  ┣ 📂 EnemySpawns (ไม่บังคับ)        <-- Part บอกจุดเกิดศัตรู ถ้าไม่มี โค้ดจะวางให้เอง
 ┃  ┗ 📂 Drops                         <-- ของที่ดรอปบนพื้น (Loot สร้างตอนเล่น)
 ┃
 ┣ 💡 Lighting                         <-- [แสงและบรรยากาศแมพ]
 ┃
 ┣ 📂 ReplicatedStorage                <-- [โซนกลาง: เห็นทั้ง Client และ Server]
 ┃  ┣ 📜 _ARCHITECTURE DON (ModuleScript) <-- โน้ต + CHANGELOG ของ DON (chwwy)
 ┃  ┣ 📜 _ARCHITECTURE WEE (ModuleScript) <-- โน้ต + CHANGELOG ของ WEE (Weerapap3006)
 ┃  ┣ 📂 Remotes
 ┃  ┃  ┣ ⚡ CombatRemote (RemoteEvent)    <-- ใช้สกิล, เลขดาเมจ, ท่าโจมตีศัตรู
 ┃  ┃  ┣ ⚡ InventoryRemote (RemoteEvent) <-- สวมใส่/ถอด/ทิ้งของ + ส่งข้อมูลกระเป๋า
 ┃  ┃  ┗ ⚡ NotifyRemote (RemoteEvent)    <-- ข้อความกลางจอ (ได้ของ, เลเวลอัป, เคลียร์ด่าน)
 ┃  ┗ 📂 Modules                       <-- ข้อมูลกลาง (ปรับตัวเลขเกมที่นี่)
 ┃     ┣ 📜 SkillData                  <-- ค่าสกิล (ดาเมจ, คูลดาวน์, ระยะ)
 ┃     ┣ 📜 EnemyData                  <-- ค่าศัตรู (เลือด, ความเร็ว, ท่าโจมตี, EXP, ตารางดรอป)
 ┃     ┣ 📜 ItemData                   <-- ไอเทมพื้นฐาน, affix, ความหายาก
 ┃     ┣ 📜 PlayerStats                <-- สเตตัสพื้นฐาน, เลือด/ดาเมจต่อเลเวล, EXP ที่ต้องใช้
 ┃     ┗ 📜 Ui                         <-- สี/ฟอนต์/ตัวช่วยสร้าง UI (Client ใช้)
 ┃
 ┣ 📂 ServerScriptService              <-- [โซน Server: ความลับ 100% กันโปร]
 ┃  ┣ 📜 CombatServer (Script)          <-- ตรวจคูลดาวน์จริง, Hitbox, คำนวณดาเมจ
 ┃  ┣ 📜 EnemyServer (Script)           <-- สั่ง EnemyService.start()
 ┃  ┗ 📜 PlayerDataServer (Script)      <-- สั่ง PlayerData.start()
 ┃
 ┣ 📂 ServerStorage                    <-- [โซน Server: โมดูลที่ Client ห้ามเห็น]
 ┃  ┗ 📂 Modules
 ┃     ┣ 📜 PlayerData                 <-- เลเวล, EXP, กระเป๋า, เซฟ/โหลด DataStore
 ┃     ┣ 📜 EnemyService               <-- เกิดศัตรู, AI ไล่ตี, ตาย -> EXP + ดรอป, เกิดใหม่
 ┃     ┗ 📜 Loot                       <-- สุ่มไอเทม + affix, วางของบนพื้นให้เก็บ
 ┃
 ┗ 📂 StarterPlayer
    ┣ 🧍 StarterCharacter (Model)       <-- หุ่น R15 Blocky สไตล์ Anime + เส้นขอบ CelShadeOutline (แก้ใน Studio)
    ┗ 📂 StarterPlayerScripts          <-- สคริปต์ฝั่ง Client
       ┣ 📜 CameraScript (LocalScript)  <-- กล้อง 2.5D Isometric + ซูม
       ┣ 📜 CombatClient (LocalScript)  <-- เล็ง, กดสกิล, แถบสกิล, VFX, เตือนท่าศัตรู, เลขดาเมจ
       ┣ 📜 HudClient (LocalScript)     <-- แถบเลือด/EXP, แถบเลือดศัตรู/บอส, ข้อความ, หน้าจอตาย
       ┣ 📜 InventoryClient (LocalScript) <-- หน้าต่างกระเป๋า
       ┗ 📜 EnemyVisualsClient (LocalScript) <-- ท่าเดินศัตรู + คุมจำนวน Highlight ไม่ให้เกิน 31
```

> UI ทั้งหมด (แถบเลือด, แถบสกิล, กระเป๋า) **สร้างจากโค้ด** ไม่มี ScreenGui ใน StarterGui ถ้าจะแก้หน้าตา UI ให้แก้ในสคริปต์ Client และสีกลางใน `Modules > Ui`

---

## 2. รายละเอียดแต่ละไฟล์ & คู่มือว่า "อยากแก้ตรงไหน ให้ไปที่ไฟล์อะไร"

### 🟦 ฝั่ง Client (`StarterPlayer > StarterPlayerScripts`)
รันบนเครื่องผู้เล่นแต่ละคน ทำหน้าที่รับ Input, บังคับกล้อง, และแสดงผลภาพ/เอฟเฟกต์ให้ลื่นไหลทันที (0 ms) **ไม่มีสิทธิ์ตัดสินดาเมจ/ของ/เลเวล**

1. **`CameraScript` (`LocalScript`)**
   * **หน้าที่:** ล็อกมุมกล้องแบบ 2.5D Isometric ตามตัวละครแบบนุ่มนวล (Smooth Lerp) และรับลูกกลิ้งเมาส์ / pinch บนมือถือ เพื่อซูมเข้า-ออก
   * **จุดที่ปรับแก้บ่อย:**
     * `BASE_OFFSET`: มุมก้มเงยและทิศทางของกล้อง (`Vector3.new(25, 35, 25)`)
     * `FIELD_OF_VIEW`: ความแบนของมุมมอง Isometric (ค่าเริ่มต้น `40`)
     * `MIN_ZOOM_DISTANCE` / `MAX_ZOOM_DISTANCE`: ระยะซูมใกล้สุด (`20`) และไกลสุด (`50`)
     * `FOLLOW_SMOOTH_SPEED` / `ZOOM_SMOOTH_SPEED`: ความนุ่มนวลเวลาเดินและซูม

2. **`CombatClient` (`LocalScript`)**
   * **หน้าที่:**
     * **PC:** ยิง Raycast จากกล้องผ่านเมาส์ลงพื้น แล้วหมุนตัวละครให้หันตามเมาส์ตลอดเวลา
     * **มือถือ:** ตัวละครหันตามทิศที่เดิน, สกิลเล็งศัตรูที่ใกล้ที่สุดเอง (ไม่เกิน `TOUCH_AUTO_AIM_RANGE`)
     * กดสกิล: **คลิกซ้าย** = ฟัน, **คลิกขวา / Q** = หมุนฟัน (กดค้างเพื่อตีต่อเนื่อง) หรือแตะปุ่มในแถบสกิล
     * เช็คคูลดาวน์เบื้องต้น (หารด้วยความเร็วโจมตีจาก attribute `AttackSpeed`) แล้วเล่น VFX ทันที และส่ง `CombatRemote:FireServer(skillId, aimPoint)`
     * ท่าฟัน = เหวี่ยงแขน (`RightShoulder`) + บิดเอว (`Waist`) ด้วย `Motor6D.Transform` ซึ่งต้องเขียนซ้ำทุกเฟรมใน `RunService.PreSimulation` (รันหลัง Animator ไม่งั้นท่าเดิน/ยืนจะทับจนมองไม่เห็น)
     * แถบสกิลพร้อมแสดงคูลดาวน์ (PC: กลางล่าง / มือถือ: ขวา เหนือปุ่มกระโดด)
     * รับ `DamageDealt` → เลขดาเมจเด้ง (ศัตรู: ขาว/คริเหลือง, ผู้เล่นโดน: แดง) + กระพริบขาว
     * รับ `ReplicateSkill` → เล่นสกิลของผู้เล่นคนอื่น
     * รับ `EnemyAttack` → เตือนก่อนโดนตี: ศัตรูธรรมดาขอบตัวเป็นสีแดง, บอสมีวงแดงบนพื้นค่อยๆ เต็ม
   * **จุดที่ปรับแก้บ่อย:**
     * `SKILL_BAR`: ลำดับสกิลบนจอและปุ่มที่ใช้กด
     * `SWING_DURATION`: เวลาเหวี่ยงออกแล้วกลับของท่าฟัน (`0.18` วิ)
     * `swingAngle` / `sideAngle` / `twist` ใน `playSlashVFX`: องศาเหวี่ยงแขนและบิดเอว
     * `SLASH_COLOR`, `ENEMY_ATTACK_COLOR`: สีคลื่นดาบของเรา / สีเตือนท่าศัตรู
     * สี / ขนาดตัวเลขดาเมจ: `label.TextColor3` และ `billboard.Size` ใน `showHitFeedback`

3. **`HudClient` (`LocalScript`)**
   * **หน้าที่:** แถบเลือด + เลเวล + EXP ของเรา (PC: ซ้ายล่าง / มือถือ: ซ้ายบน), แถบเลือดเล็กบนหัวศัตรูทุกตัวใน `Workspace.Enemies`, แถบเลือดบอสใหญ่ด้านบนเมื่ออยู่ใกล้บอส, ข้อความจาก `NotifyRemote`, หน้าจอ "คุณตายแล้ว" พร้อมนับถอยหลังเกิดใหม่ และปิดแถบเลือดเดิมของ Roblox
   * **จุดที่ปรับแก้บ่อย:** `BOSS_BAR_RANGE` (ระยะที่แถบบอสขึ้น), `NOTIFY_DURATION`, `MAX_NOTIFICATIONS`

4. **`InventoryClient` (`LocalScript`)**
   * **หน้าที่:** หน้าต่างกระเป๋า (กด **I** หรือปุ่ม "กระเป๋า") ซ้าย = ของที่สวมใส่ + สเตตัส, กลาง = ช่องของ, ขวา = รายละเอียดไอเทมที่เลือก + ปุ่ม สวมใส่/ถอด/ทิ้ง (ทิ้งต้องกด 2 ครั้ง)
   * แค่ **แสดงผล** ข้อมูลล่าสุดที่ Server ส่งมา (`"Sync"`) และส่งคำขอไปให้ Server ตัดสิน
   * **จุดที่ปรับแก้บ่อย:** `TOGGLE_KEY`, `GRID_COLUMNS`, `CELL_SIZE`

5. **`EnemyVisualsClient` (`LocalScript`)**
   * **ท่าเดินศัตรู:** แกว่งแขนขา (Motor6D `LeftHip`, `RightHip`, `LeftShoulder`, `RightShoulder` ที่ `EnemyService` สร้าง) ตามความเร็วที่ศัตรูเคลื่อนที่จริง หยุดเดิน = ค่อยๆ กลับท่ายืน ทำใน `RunService.PreSimulation` เหมือนท่าฟันของผู้เล่น
   * **คุม Highlight:** Roblox แสดง Highlight พร้อมกันได้แค่ 31 อัน (เกินแล้วหายเฉยๆ) สคริปต์นี้เรียง Highlight **ทุกอัน** ใน Workspace (ศัตรู, ผู้เล่น, คลื่นดาบ) ตามระยะจากตัวเรา แล้วเปิดแค่ 27 อันที่ใกล้สุด (เหลือ 4 ที่ให้คลื่นดาบที่เกิดระหว่างรอบ) ทุก 0.2 วิ
     * ⚠ อยากซ่อน Highlight ให้ **ลบทิ้ง** อย่าตั้ง `Enabled = false` เพราะสคริปต์นี้จะเปิดกลับ (ยกเว้นอันที่ปิดไว้ตั้งแต่ตอนสร้าง สคริปต์จะไม่ยุ่ง)
   * **จุดที่ปรับแก้บ่อย:** `LEG_SWING` / `ARM_SWING` (องศาแกว่ง), `STRIDE_LENGTH` (ก้าวยาวแค่ไหน), `HIGHLIGHT_HEADROOM`

---

### 🟨 โซนตรงกลาง (`ReplicatedStorage`)
ทั้ง Client และ Server มองเห็นและเรียกใช้ร่วมกันได้

1. **`Remotes`** (ท่อส่งข้อมูล Client ↔ Server)

   | Remote | ทิศทาง | ข้อความ |
   |---|---|---|
   | `CombatRemote` | Client → Server | `(skillId, aimPoint)` เมื่อใช้สกิล |
   | | Server → ทุก Client | `("ReplicateSkill", character, skillId, aimPoint, step)` ให้คนอื่นเห็นสกิลเรา |
   | | Server → ทุก Client | `("DamageDealt", targetModel, damage, isCrit)` เลขดาเมจ (ทั้งศัตรูและผู้เล่น) |
   | | Server → ทุก Client | `("EnemyAttack", enemyModel, kind, center, radius, windup)` เตือนท่าศัตรู |
   | `InventoryRemote` | Client → Server | `("RequestSync")`, `("Equip", itemId)`, `("Unequip", slot)`, `("Discard", itemId)` |
   | | Server → Client | `("Sync", { Inventory, Equipped, Capacity })` ข้อมูลกระเป๋าทั้งหมด |
   | `NotifyRemote` | Server → Client | `(text, color?)` ข้อความกลางจอ |

2. **`Modules > SkillData`** — ค่าสกิลทั้งหมด
   * ดาเมจจริง = สุ่ม `MinDamage`–`MaxDamage` + สเตตัส `FlatDamage` ของผู้เล่น, คูณ `CritMultiplier` ถ้าติดคริ (`CritChance`)
   * คูลดาวน์จริง = `Cooldown / (1 + AttackSpeed% / 100)` (ฟัน `0.55` วิ, หมุนฟัน `3` วิ)
   * `Shape = "Box"` ใช้ `HitboxSize` + `HitboxForwardOffset` (กล่องหน้าตัว), `Shape = "Radius"` ใช้ `Radius` (วงรอบตัว)

3. **`Modules > EnemyData`** — ศัตรูแต่ละชนิด (key = ชื่อที่ใช้ตั้งจุดเกิด)
   * `MaxHealth`, `WalkSpeed` (ผู้เล่นเดิน 18), `Scale` (ขนาดตัว), สีตัว/ตา
   * `AggroRange` = ระยะที่เริ่มไล่, `LeashRange` = ถูกล่อไกลจากจุดเกิดเกินนี้จะเดินกลับบ้านและเลือดเต็ม
   * `Attack`: `Kind` (`Melee` ตีคนเดียว / `Slam` ทุบเป็นวง `Radius`), `Range`, `Windup` (เวลาเตือนก่อนโดน = เวลาให้หลบ), `Cooldown`, ดาเมจ
   * `Exp` (ทุกคนที่ตีโดนได้เต็มจำนวน), `RespawnTime`, `Drops` (`Rolls` ครั้ง × โอกาส `Chance`, `RarityWeights` = น้ำหนักความหายาก)

4. **`Modules > ItemData`** — ไอเทม
   * `Bases`: ของที่ดรอปได้ (`IronSword` ดาบเหล็ก → ช่องอาวุธ, `LeatherVest` เสื้อเกราะหนัง → ช่องเกราะ) พร้อม `Implicit` = สเตตัสติดตัวของทุกชิ้น
   * `Affixes`: ออปชันสุ่ม `FlatDamage` (+ดาเมจ, Prefix), `MaxHealth` (+เลือด, Prefix), `AttackSpeed` (+% ความเร็วโจมตี, Suffix) แต่ละอันมีช่วงค่า `Min`–`Max`
   * `Rarities`: ธรรมดา (0 affix, ขาว), เวทมนตร์ (1-2, ฟ้า, Prefix ≤1 Suffix ≤1), หายาก (3, เหลือง)
   * ไอเทม 1 ชิ้นเป็นข้อมูลล้วน `{ Id, Base, Rarity, Affixes = { { Id, Value } } }` จึงเซฟลง DataStore และส่งผ่าน Remote ได้ตรงๆ
   * **เพิ่มไอเทม/affix ใหม่:** เพิ่มแถวใน `Bases` / `Affixes` (ถ้าเป็นสเตตัสใหม่ต้องเพิ่มใน `StatText`, `PlayerStats` และโค้ดที่ใช้สเตตัสนั้นด้วย)

5. **`Modules > PlayerStats`** — สเตตัสผู้เล่น
   * `BASE_MAX_HEALTH` (100), `MAX_HEALTH_PER_LEVEL` (+12/เลเวล), `DAMAGE_PER_LEVEL` (+2/เลเวล), `MAX_LEVEL` (30)
   * `expToNext(level)` = EXP ที่ต้องใช้ขึ้นเลเวลถัดไป (`60 + level × 40`)
   * `compute(level, equipped)` = สเตตัสสุดท้าย, `getCooldown(...)` = คูลดาวน์หลังคิดความเร็วโจมตี (Client และ Server ใช้สูตรเดียวกัน)

6. **`Modules > Ui`** — สี (`Ui.Colors`), ฟอนต์, ตัวช่วยสร้าง UI (`Ui.new`, `Ui.text`, `Ui.button`) และ `Ui.isTouchOnly()` (เช็คว่าเป็นมือถือ)

---

### 🟥 ฝั่ง Server (`ServerScriptService` + `ServerStorage > Modules`)
รันบนเซิร์ฟเวอร์ของ Roblox เท่านั้น ผู้เล่นและโปรโกงไม่สามารถมองเห็นหรือแก้ไขได้ **ทุกอย่างที่มีผลต่อเกม (ดาเมจ, ของ, EXP, เลเวล) ตัดสินที่นี่**

`Script` ใน ServerScriptService เป็นแค่ตัวเริ่ม ระบบจริงอยู่ใน ModuleScript ที่ `ServerStorage > Modules` เพื่อให้หลายสคริปต์เรียกใช้กันได้ (เช่น CombatServer เรียก `EnemyService.applyDamage`)

1. **`CombatServer` (`Script`)**
   * **Anti-Exploit Check:** ตรวจชนิดข้อมูลที่ส่งมา, ตัวละครยังมีชีวิต, คูลดาวน์จริงแยกตามสกิล (`playerCooldowns`, หักความเร็วโจมตีจาก `PlayerData.getStats`)
   * **Server Hitbox:** `GetPartBoundsInBox` (ฟัน) หรือ `GetPartBoundsInRadius` (หมุนฟัน) หา Model ที่มี Humanoid **ข้ามตัวละครผู้เล่น** (เล่นด้วยกัน ไม่ตีกันเอง)
   * **Damage:** สุ่มดาเมจ + `FlatDamage` → ศัตรูของ `EnemyService` ส่งต่อให้ `EnemyService.applyDamage` (จัดการตาย/EXP/ดรอปเอง), ตัวอื่น (TrainingDummy) ใช้ `TakeDamage` ตรงๆ

2. **`EnemyServer` (`Script`)** → `EnemyService.start()`

3. **`PlayerDataServer` (`Script`)** → `PlayerData.start()`

4. **`ServerStorage > Modules > EnemyService`**
   * **จุดเกิด:** อ่าน Part ใน `Workspace.EnemySpawns` ถ้าไม่มีโฟลเดอร์นี้จะวางด่านเริ่มต้นให้เอง (ลูกสมุน 2 กลุ่ม กลุ่มละ 3 + บอส 1 ห่างจาก SpawnLocation ~40-80 studs)
   * **ตัวศัตรู:** สร้างหุ่น Blockout จากโค้ด (`BODY_PARTS`: ตัว หัว ตา เชื่อม WeldConstraint กับ HumanoidRootPart, แขนขาต่อด้วย Motor6D ที่หมุนจากหัวไหล่/สะโพก ให้ `EnemyVisualsClient` แกว่งเป็นท่าเดิน) + Highlight เส้นขอบการ์ตูน
   * **AI (ทุก `AI_TICK` = 0.15 วิ):** หาผู้เล่นใกล้สุดใน `AggroRange` → เดินเข้าหา → ถึง `Attack.Range` และคูลดาวน์พร้อม → หยุด หันหน้า ส่ง `EnemyAttack` ให้ Client เตือน → รอ `Windup` → Melee: ตีโดนถ้าเป้ายังอยู่ใน `Range + 1.5`, Slam: โดนทุกคนในวง `Radius` (มี ForceField ตอนเกิด = ไม่โดน)
   * **การเดิน (`moveToward`):** กวาดกล่องขนาดตัวศัตรู (`Blockcast`) ไปทางเป้า ถ้าโล่ง = เดินตรง ถ้ามีกำแพงขวาง = ขอเส้นทางจาก `PathfindingService` (ขนาดตัวตาม `Scale`, กระโดดไม่ได้) แล้วเดินตาม waypoint คำนวณใหม่เมื่อเป้าขยับเกิน `PATH_GOAL_TOLERANCE` (ไม่ถี่กว่าทุก `PATH_REFRESH_TIME` = 1 วิ) หาทางไม่ได้ = เดินตรงไปเหมือนเดิม ใช้ทั้งตอนไล่และตอนเดินกลับบ้าน
   * โดนตีจากนอกระยะ = หันมาไล่คนตีทันที, ถูกล่อเกิน `LeashRange` = เดินกลับบ้าน เลือดเต็ม
   * **เลือดตามจำนวนผู้เล่น:** `MaxHealth × (1 + HEALTH_PER_EXTRA_PLAYER × (ผู้เล่น − 1))` (+50% ต่อคนที่เพิ่ม) ปรับทุกตัวทันทีตอนมีคนเข้า/ออก โดยคง % เลือดเดิม (EXP และของดรอปไม่เปลี่ยน)
   * **ตาย:** EXP ให้ทุกคนที่เคยตีโดน → `Loot.rollDrops` → บอสตายประกาศ "เคลียร์ด่าน!" ทุกคน → ศพจางหาย 1 วิ → เกิดใหม่ที่เดิมหลัง `RespawnTime`

5. **`ServerStorage > Modules > Loot`**
   * `rollItem(rarity)`: สุ่มฐานไอเทม → จำนวน affix ตามความหายาก → สับ affix แล้วหยิบตามโควตา Prefix/Suffix → สุ่มค่าในช่วง `Min`–`Max`
   * `dropItem`: วางก้อน Neon สีตามความหายาก + ชื่อลอย + `ProximityPrompt` "เก็บ" (กด **E** / แตะบนมือถือ) → `PlayerData.addItem` (กระเป๋าเต็ม = เก็บไม่ได้ ของยังอยู่)
   * **จุดที่ปรับแก้บ่อย:** `DROP_LIFETIME` (ของหายเองหลัง 90 วิ), `PICKUP_DISTANCE`, `SCATTER`

6. **`ServerStorage > Modules > PlayerData`**
   * ข้อมูลผู้เล่นใน memory: `Level`, `Exp`, `Inventory` (สูงสุด `INVENTORY_CAPACITY` = 20), `Equipped` (ช่องละ 1 ชิ้น), `Stats`
   * **โหลด:** เข้าเกม → `GetAsync` (ลองใหม่ 3 ครั้ง) → ล้างข้อมูลที่เกมไม่รู้จักแล้วทิ้ง (เช่นไอเทมที่ถูกลบออกจาก `ItemData`) → ส่ง `Sync` + ตั้ง attribute
   * **กันข้อมูลหาย:** ถ้าโหลดไม่สำเร็จ จะเล่นได้แต่ `CanSave = false` (ไม่เซฟทับข้อมูลจริงด้วยโปรไฟล์ว่าง) และแจ้งผู้เล่น
   * **เทสใน Studio:** ถ้า Studio ไม่มีสิทธิ์ใช้ DataStore (เช่น `game.rbxl` หรือยังไม่เปิด API Services) จะไม่ลองซ้ำ ขึ้นข้อความ "เทสใน Studio: เล่นได้ปกติ แต่ไม่บันทึกความคืบหน้า" และพิมพ์วิธีเปิดสิทธิ์ไว้ใน Output
   * **เซฟ:** ตอนออกเกม, ทุก `AUTOSAVE_INTERVAL` (120 วิ), และตอนเซิร์ฟเวอร์ปิด (`BindToClose` รอเซฟเสร็จสูงสุด 25 วิ) ใช้ `UpdateAsync` ลองใหม่ 3 ครั้ง
   * **กระเป๋า:** สวมใส่ = สลับกับของเดิมในช่องเดียวกัน, ถอด = ต้องมีที่ว่างในกระเป๋า, ทิ้ง = ลบถาวร ทุกคำขอเช็คว่าของเป็นของผู้เล่นคนนั้นจริง
   * **เลเวลอัป:** EXP ครบ `expToNext` → เลเวล +1, เลือดเต็ม, แจ้งเตือน
   * `DATASTORE_NAME = "PlayerData_v1"`: **เปลี่ยนชื่อ = ข้อมูลทุกคนเริ่มใหม่หมด**

#### Attribute บนตัว Player (Server ตั้ง → Client อ่าน)

| Attribute | ความหมาย | ใครใช้ |
|---|---|---|
| `Level`, `Exp`, `ExpToNext` | เลเวลและ EXP | HudClient, InventoryClient |
| `MaxHealth`, `FlatDamage`, `AttackSpeed` | สเตตัสสุดท้าย | InventoryClient, CombatClient (คูลดาวน์) |
| `DataStatus` | `Loading` / `Loaded` / `Failed` / `NoAccess` (Studio ไม่มีสิทธิ์ DataStore) | (ไว้เช็คตอน debug) |

#### Attribute บนตัวศัตรู
`DisplayName`, `IsBoss` (EnemyService ตั้ง → HudClient ใช้แสดงชื่อและแถบบอส)

---

### 🧍 หุ่นตัวละครพื้นฐาน (`StarterPlayer > StarterCharacter`)
* **หน้าที่:** บังคับให้ผู้เล่นทุกคนที่เข้าเกมใช้หุ่น R15 Blocky สัดส่วน Anime เดียวกันทั้งหมด
* **องค์ประกอบสำคัญในตัวหุ่น:**
  * `CelShadeOutline` (`Highlight`): เส้นตัดขอบสีดำรอบตัวละคร (กระพริบขาวตอนโดนตีด้วย)
  * `Humanoid`: ตั้งค่า `WalkSpeed = 18` และปิดการแสดงชื่อบนหัว — `MaxHealth` ถูก `PlayerData` ตั้งใหม่ทุกครั้งที่เกิดตามเลเวล + ของที่สวมใส่

---

## 3. สิ่งที่โค้ดต้องการจากแมพ (คนแต่งแมพต้องอ่าน)

* **`Workspace.Enemies`**: โฟลเดอร์ศัตรู (ถ้าไม่มี โค้ดสร้างให้) — Model ที่มี Humanoid + HumanoidRootPart ข้างในจะมีแถบเลือดและโดนตีได้
* **ด่าน = `Workspace.EnemySpawns`** (โฟลเดอร์ ไม่บังคับ): ใส่ Part วางบนพื้นตรงจุดที่อยากให้ศัตรูเกิด
  * ตั้งชื่อ Part เป็นชนิดศัตรู (`Grunt` หรือ `Brute`) หรือใส่ Attribute `EnemyType` = ชื่อนั้น
  * Part ซ่อนตัวเองตอนเริ่มเกม ตั้ง Anchored ไว้ จะใส่ Part ในโฟลเดอร์ย่อยก็ได้
  * ถ้าไม่มีโฟลเดอร์นี้ (หรือไม่มี Part ที่ถูกต้องเลย) จะใช้ด่านเริ่มต้นรอบ SpawnLocation
  * ศัตรูหาพื้นด้วยการยิง Raycast ลงจาก 10 studs เหนือ Part ห้ามมีหลังคา/สิ่งกีดขวางอยู่ในระยะนั้น
* **ทางเดินต้องกว้างพอ** ให้บอส (`Scale = 2.4`, pathfinding ต้องการทางกว้าง ~10 studs) ศัตรูเดินอ้อมกำแพงได้ แต่ **กระโดดไม่ได้** ทางที่ต้องกระโดดขึ้น = ศัตรูตามไปไม่ได้
* ของตกแต่งที่ไม่อยากให้ขวางทางศัตรู (หญ้า, ป้าย) ตั้ง `CanCollide = false` ศัตรูจะมองข้าม
* Highlight ที่ใส่ในแมพจะถูก `EnemyVisualsClient` เปิด/ปิดตามระยะด้วย อยากซ่อนให้ลบทิ้ง
* `TrainingDummy` เป็นศัตรูที่ทำใน Studio เอง (ไม่ได้อยู่ใน EnemyData) → โดนตีได้ แต่ไม่ให้ EXP/ของ

---

## 4. ลำดับการทำงาน (Flows)

### 4.1 ผู้เล่นใช้สกิล

```mermaid
sequenceDiagram
    participant C as CombatClient
    participant R as CombatRemote
    participant S as CombatServer
    participant E as EnemyService

    C->>C: 1. หันหน้าตามเมาส์ (PC) / เล็งศัตรูใกล้สุด (มือถือ)
    C->>C: 2. กดสกิล -> เช็ค Cooldown เบื้องต้น
    C->>C: 3. เล่นท่า + VFX ทันที (คลื่นดาบ / วงหมุน)
    C->>R: 4. FireServer(skillId, aimPoint)
    R->>S: 5. ส่งคำขอไปที่ Server
    S->>S: 6. เช็ค Cooldown จริง (หักความเร็วโจมตี)
    S->>R: 7. FireAllClients("ReplicateSkill", ...) ให้คนอื่นเห็น
    S->>S: 8. Hitbox (กล่อง / วงกลม) หาศัตรู ข้ามผู้เล่น
    S->>E: 9. applyDamage(enemy, damage, player)
    E->>E: 10. หักเลือด + จดว่าใครตี (เลือดหมด -> หัวข้อ 4.3)
    S->>R: 11. FireAllClients("DamageDealt", enemy, damage, isCrit)
    R->>C: 12. เลขดาเมจเด้ง + ศัตรูกระพริบขาว
```

### 4.2 ศัตรูโจมตีผู้เล่น

```mermaid
sequenceDiagram
    participant E as EnemyService (AI ทุก 0.15 วิ)
    participant R as CombatRemote
    participant C as CombatClient

    E->>E: 1. หาผู้เล่นใกล้สุดใน AggroRange แล้วเดินเข้าหา
    E->>E: 2. ถึงระยะ Attack.Range -> หยุด หันหน้า
    E->>R: 3. FireAllClients("EnemyAttack", enemy, kind, center, radius, windup)
    R->>C: 4. แสดงคำเตือน (ขอบแดง / วงแดงบนพื้น)
    E->>E: 5. รอ Windup (ผู้เล่นหลบได้)
    E->>E: 6. เช็คว่ายังอยู่ในระยะ -> TakeDamage
    E->>R: 7. FireAllClients("DamageDealt", character, damage)
```

### 4.3 ฆ่าศัตรู → EXP → ดรอป → เก็บของ → เซฟ

1. `Humanoid.Died` ของศัตรู → `EnemyService` ให้ EXP ทุกคนที่ตีโดน (`PlayerData.addExp` → อาจเลเวลอัป)
2. `Loot.rollDrops(EnemyData.Drops)` → สุ่มไอเทมบน Server → วางก้อนของบนพื้น
3. ผู้เล่นกด **E** / แตะ "เก็บ" → `PlayerData.addItem` → `InventoryRemote "Sync"` + ข้อความ "ได้รับ ..."
4. เปิดกระเป๋า → กดสวมใส่ → `InventoryRemote ("Equip", id)` → Server สลับของ → คำนวณสเตตัสใหม่ → ตั้ง attribute + MaxHealth → `Sync`
5. ทั้งหมดถูกเซฟลง DataStore ตอนออกเกม / ทุก 2 นาที / ตอนเซิร์ฟเวอร์ปิด

---

## 5. ข้อจำกัดที่รู้แล้ว

* **`Workspace.Script1`** สคริปต์ว่าง 3 ตัว (print "Hello world!") ปนอยู่ในแมพ ต้องลบใน Studio (แมพอยู่ใน Team Create แก้จากโค้ดไม่ได้)
* **ทดสอบการเซฟใน `game.rbxl` ไม่ได้** (Studio ไม่มีสิทธิ์ DataStore) เกมจะเล่นได้แต่ไม่เซฟ ทดสอบการเซฟใน Team Create ที่เปิด Game Settings → Security → **Enable Studio Access to API Services**
* **ยังไม่ได้ playtest บาลานซ์** ตัวเลขตอนนี้มาจากการคำนวณ (เลเวล 1 ไม่มีของ, ตีโดนทุกครั้ง, ฟันเฉลี่ย ~47 ดาเมจรวมคริ):

  | สถานการณ์ | เวลาโดยประมาณ |
  |---|---|
  | ฆ่าภูตหิน (120 HP) | 3 ฟัน ~1.1 วิ |
  | บอสคนเดียว (1500 HP) | ~14 วิ ถ้ายืนตีตลอด, ~15-20 วิ รวมเวลาหลบทุบ |
  | บอส 2 คน (2250 HP) | ~10-15 วิ |
  | ภูตหิน 3 ตัวรุมเรา (เลือด 100) | ตายใน ~7 วิ ถ้ายืนเฉยๆ |

* ศัตรูยังไม่มีท่าง้างตอนโจมตี (มีแค่ท่าเดิน + ขอบแดง/วงแดงเตือน) และ pathfinding ไม่กระโดด
* ศัตรูที่ไกลกว่า Highlight อันที่ 27 จะไม่มีเส้นขอบ (ตั้งใจ เพื่อไม่ให้เกินขีดจำกัด 31 ของ Roblox)
