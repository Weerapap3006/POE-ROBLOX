# Project poe (POE-ROBLOX)

เกม ARPG แนว 2.5D Isometric บน Roblox ทำกัน 2 คนผ่าน Team Create

- **โค้ด** (ทุกอย่างในโฟลเดอร์ `src/`) เก็บใน GitHub repo นี้ แก้ใน VS Code แล้วให้ Rojo sync เข้า Studio
- **แมพ / โมเดล / StarterCharacter** อยู่ใน Team Create แก้ใน Studio ได้ตามปกติ

โน้ตโครงสร้างเกม, ไฟล์ไหนแก้อะไร และบันทึกการแก้ไข **แยกคนละไฟล์** (จด CHANGELOG ในของตัวเอง ห้ามแก้ของอีกคน):

- **DON** (chwwy) → [`src/ReplicatedStorage/_ARCHITECTURE DON.luau`](src/ReplicatedStorage/_ARCHITECTURE%20DON.luau)
- **WEE** (Weerapap3006) → [`src/ReplicatedStorage/_ARCHITECTURE WEE.luau`](src/ReplicatedStorage/_ARCHITECTURE%20WEE.luau)

อธิบายแต่ละระบบแบบละเอียด (หน้าที่ของแต่ละสคริปต์, flow การต่อสู้ Client ↔ Server) ดูที่ [`ARCHITECTURE.md`](ARCHITECTURE.md)

---

## ตั้งค่าครั้งแรก (ทำครั้งเดียว)

ทุกคำสั่งข้างล่างพิมพ์ใน **PowerShell**

### 1. ลง Git และ VS Code

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.VisualStudioCode -e
```

### 2. ลง Rojo 7.7.1

ต้องใช้ **7.7.1** เหมือนกันทั้งสองคน ถ้าเวอร์ชันไม่ตรง ปลั๊กอินใน Studio อาจต่อไม่ติด

```powershell
$dir = "$env:LOCALAPPDATA\Programs\rojo"
New-Item -ItemType Directory -Force $dir | Out-Null
Invoke-WebRequest "https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-windows-x86_64.zip" -OutFile "$env:TEMP\rojo.zip"
Expand-Archive "$env:TEMP\rojo.zip" -DestinationPath $dir -Force
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$dir", "User")
```

**ปิด PowerShell แล้วเปิดใหม่** (ไม่งั้นจะยังหาคำสั่งไม่เจอ) แล้วเช็ก:

```powershell
git --version     # ต้องขึ้น git version ...
rojo --version    # ต้องขึ้น Rojo 7.7.1
```

### 3. ลงปลั๊กอิน Rojo ใน Roblox Studio

ปิด Studio ก่อน แล้วสั่ง:

```powershell
rojo plugin install
```

เปิด Studio ใหม่ จะเห็นปุ่ม **Rojo** ในแท็บ **Plugins**

### 4. ตั้งชื่อที่จะขึ้นใน commit

ใช้อีเมลเดียวกับบัญชี GitHub ของตัวเอง

```powershell
git config --global user.name "ชื่อของคุณ"
git config --global user.email "อีเมล GitHub ของคุณ"
```

### 5. รับคำเชิญ repo แล้ว clone

1. เปิด <https://github.com/Weerapap3006/POE-ROBLOX/invitations> แล้วกด **Accept invitation** (ถ้าไม่มี ให้เจ้าของ repo เชิญก่อน: Settings → Collaborators)
2. clone ลงเครื่อง (ใส่ที่ไหนก็ได้ ตัวอย่างนี้ใส่ใน Desktop):

   ```powershell
   cd $HOME\Desktop
   git clone https://github.com/Weerapap3006/POE-ROBLOX.git
   ```

   ครั้งแรกจะมีหน้าต่างให้ login GitHub ให้กด **Sign in with your browser** แล้ว **Authorize**
3. เปิด VS Code → **File → Open Folder** → เลือกโฟลเดอร์ `POE-ROBLOX`

### 6. (แนะนำ) Extension ใน VS Code

- **Luau Language Server** (`JohnnyMorganz.luau-lsp`) ช่วยเติมโค้ดและเตือน error ของ Luau

---

## ทุกครั้งที่ทำงาน

ใน Team Create **Rojo ยอมให้ Connect ได้ทีละคน** (ตอนมีคน Connect อยู่จะเห็น `__Rojo_SessionLock` ใน ServerStorage) เลยแบ่งงานเป็น 3 แบบ:

| งาน | ทำที่ไหน | ใช้ Rojo? |
|---|---|---|
| 🗺️ แต่งแมพ | Team Create | ไม่ใช้ |
| 💻 เขียน/เทสโค้ด | **place สำเนา** ในเครื่องตัวเอง (`game.rbxl`) | ใช้ (ไม่ต้องรอกัน) |
| 🚀 ส่งโค้ดเข้าเกมจริง | Team Create | ใช้ **ทีละคน** แล้วรีบ Disconnect |

### 🗺️ แต่งแมพ

เปิด place **Project poe** ผ่าน Team Create แล้วแก้ใน Studio ได้เลย ไม่ต้องใช้ Rojo หรือ Git

### 💻 เขียนและเทสโค้ด

**ทำสำเนา place** (ครั้งแรก หรือตอนอยากได้แมพล่าสุดมาเทส):
เปิด Team Create → **File → Save to File As...** → บันทึกเป็น `game.rbxl` ในโฟลเดอร์ `POE-ROBLOX` (ทับของเดิมได้ ไฟล์นี้ไม่ขึ้น git)

**ทุกครั้งที่เขียนโค้ด** (Terminal ใน VS Code: `` Ctrl+` ``):

1. ดึงโค้ดล่าสุดของเพื่อน: `git pull`
2. เปิด Rojo: `rojo serve` (ปล่อย terminal นี้รันค้างไว้)
3. ใน Studio: **File → Open from File** → เปิด `game.rbxl` → **Plugins → Rojo → Connect**
4. แก้โค้ดใน VS Code → เซฟ (Rojo ส่งเข้า Studio ทันที) → กด Play ทดสอบ
5. จดลง CHANGELOG ในโน้ตของตัวเอง (`_ARCHITECTURE DON` หรือ `_ARCHITECTURE WEE`) ว่าแก้อะไร
6. เสร็จแต่ละเรื่อง ส่งขึ้น GitHub ทันที (อย่าเก็บไว้ข้ามวัน):

   ```powershell
   git add .
   git commit -m "อธิบายสั้นๆ ว่าแก้อะไร"
   git pull
   git push
   ```

> ⚠️ **ห้ามกด Publish to Roblox จาก `game.rbxl`** เพราะแมพในสำเนาเป็นของเก่า จะไปทับงานแมพใน Team Create

### 🚀 ส่งโค้ดเข้าเกมจริง (Team Create)

ทำเมื่อโค้ดบน GitHub พร้อมแล้ว **ทีละคน**:

1. `git pull` เพื่อให้มีโค้ดล่าสุดของทั้งสองคน
2. `rojo serve`
3. เปิด Team Create → **Plugins → Rojo → Connect**
   - Rojo จะโชว์รายการที่จะเปลี่ยนก่อน ควรมีแต่สคริปต์ที่เพิ่ง push
   - ถ้ามีอะไรแปลกๆ (เช่นสคริปต์ที่ไม่ได้มีใครแก้) → กด **Abort** แล้วถามกันก่อน
4. กด **Disconnect** ทันทีที่ sync เสร็จ เพื่อปล่อยให้อีกคนใช้ได้
5. ถ้า Connect ไม่ได้เพราะอีกคน sync อยู่ ให้รอเขา Disconnect ก่อน

---

## แยกงาน: แมพ = Studio / โค้ด = VS Code + GitHub

| 🗺️ แมพ → แก้ใน **Roblox Studio** (อยู่ใน Team Create, ไม่ขึ้น GitHub) | 💻 โค้ด → แก้ใน **VS Code** แล้ว push ขึ้น **GitHub** |
|---|---|
| ทุกอย่างใน Workspace (`Enemies/TrainingDummy`, ด่านกับประตูวาร์ป `DungeonMap`, จุดเกิดศัตรู `EnemySpawns`, พื้น, Terrain ฯลฯ) | ทุกสคริปต์ที่มีไฟล์อยู่ใน `src/` เช่น `SkillData`, `EnemyData`, `ItemData`, `CombatServer`, `PlayerData`, `EnemyService`, `CombatClient`, `HudClient`, `InventoryClient`, `EnemyVisualsClient`, `MinimapClient`, `_ARCHITECTURE DON`, `_ARCHITECTURE WEE` (รายการเต็มใน [`ARCHITECTURE.md`](ARCHITECTURE.md)) |
| `StarterPlayer.StarterCharacter` | ถ้าไปแก้สคริปต์พวกนี้ใน Studio จะ**โดน Rojo เขียนทับ**ตอนใครก็ตามกด Connect หรือเซฟไฟล์นั้น |
| Lighting, Teams, SoundService, หน้าตา UI ใน StarterGui | ลบใน Studio → Rojo สร้างกลับมา, เปลี่ยนชื่อ → ได้ตัวซ้ำ 2 ตัว |
| | UI ตอนนี้ (แถบเลือด, แถบสกิล, กระเป๋า, มินิแมพ, หน้าตั้งค่า) **สร้างจากโค้ด** ไม่ได้อยู่ใน StarterGui |

**ของใหม่ใส่ที่ไหน**

- **สคริปต์ทุกตัวที่เขียนเอง** → สร้างเป็นไฟล์ใน `src/` เสมอ ห้ามกด Insert Script ใน Studio
  - ฝั่ง server → `src/ServerScriptService/ชื่อ.server.luau`
  - ฝั่ง client → `src/StarterPlayer/StarterPlayerScripts/ชื่อ.client.luau`
  - ใช้ร่วมกัน → `src/ReplicatedStorage/Modules/ชื่อ.luau`
  - โมดูลที่ให้แค่ server ใช้ (client มองไม่เห็น) → `src/ServerStorage/Modules/ชื่อ.luau`
- **Part / Model / Terrain / แสง / เสียง / หน้าตา UI** → สร้างใน Studio
- ข้อยกเว้น: LocalScript `Animate` ใน TrainingDummy และ StarterCharacter เป็นสคริปต์ท่าเดินที่ติดมากับหุ่น R15 ปล่อยไว้ในโมเดลได้

คนแต่งแมพต้องอ่าน **"สิ่งที่โค้ดต้องการจากแมพ"** ในหัวข้อ 3 ของ [`_ARCHITECTURE DON.luau`](src/ReplicatedStorage/_ARCHITECTURE%20DON.luau) ด้วย เช่น ศัตรูต้องมี Humanoid กับ HumanoidRootPart, StarterCharacter ต้องเป็น R15 ถ้าทำข้อพวกนี้หลุด โค้ดจะพังโดยไม่ขึ้น error

**กันทับงานกัน**

- แบ่งงานกันคนละไฟล์ ถ้าต้องแก้ไฟล์เดียวกันให้บอกกันก่อน
- ถ้าแก้แมพพร้อมกันใน Team Create ให้บอกกันว่าใครแต่งโซนไหน

---

## ปัญหาที่เจอบ่อย

| อาการ | วิธีแก้ |
|---|---|
| `git` หรือ `rojo` is not recognized | ปิด VS Code / PowerShell แล้วเปิดใหม่ (PATH อัปเดตตอนเปิดโปรแกรม) |
| `git push` ขึ้น **rejected** / **fetch first** | เพื่อน push ก่อนเรา → `git pull` แล้ว `git push` ใหม่ |
| `git pull` ขึ้น **CONFLICT** | สองคนแก้บรรทัดเดียวกัน → เปิดไฟล์ใน VS Code เลือก Accept Current (ของเรา) / Incoming (ของเพื่อน) / Both แล้ว `git add .` → `git commit` → `git push` |
| CHANGELOG conflict | เกิดบ่อยเพราะต่างคนเพิ่มบรรทัดบนสุด → กด **Accept Both** |
| Rojo กด Connect ไม่ติด | เช็กว่ายังมี terminal ที่รัน `rojo serve` อยู่ และ `rojo --version` เป็น 7.7.1 |
| ปลั๊กอินเตือนเวอร์ชันไม่ตรง | ปิด Studio แล้วสั่ง `rojo plugin install` ใหม่ |
| เข้าเกมแล้วขึ้น "Studio Test: Playable, but progress will not be saved" | ปกติใน `game.rbxl` (สำเนาในเครื่องใช้ DataStore ไม่ได้) ถ้าอยากเทสการเซฟ ให้เทสใน Team Create ที่เปิด **Game Settings → Security → Enable Studio Access to API Services** |
| เข้าเกมแล้วขึ้น "Failed to load data. Progress will not be saved this session" | DataStore ของ Roblox มีปัญหาชั่วคราว (ลองแล้ว 3 รอบ) รอบนั้นจะไม่เซฟ กันข้อมูลเก่าโดนทับ ออกแล้วเข้าใหม่ |
