# Project poe (POE-ROBLOX)

เกม ARPG แนว 2.5D Isometric บน Roblox ทำกัน 2 คนผ่าน Team Create

- **โค้ด** (ทุกอย่างในโฟลเดอร์ `src/`) เก็บใน GitHub repo นี้ แก้ใน VS Code แล้วให้ Rojo sync เข้า Studio
- **แมพ / โมเดล / StarterCharacter** อยู่ใน Team Create แก้ใน Studio ได้ตามปกติ

โครงสร้างเกมทั้งหมด, ไฟล์ไหนแก้อะไร และบันทึกการแก้ไข ดูได้ที่ [`src/ReplicatedStorage/_ARCHITECTURE.luau`](src/ReplicatedStorage/_ARCHITECTURE.luau)

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

1. **ดึงโค้ดล่าสุดของเพื่อนก่อนเสมอ** (Terminal ใน VS Code: `` Ctrl+` ``)

   ```powershell
   git pull
   ```

2. **เปิด Rojo** (ปล่อย terminal นี้รันค้างไว้ อย่าปิด)

   ```powershell
   rojo serve
   ```

3. **เปิด Studio** → เข้า place **Project poe** ผ่าน Team Create → แท็บ **Plugins** → **Rojo** → **Connect**
   - Rojo จะโชว์รายการสคริปต์ที่จะถูกเปลี่ยนก่อน
   - **ถ้ามีสคริปต์ที่เราไม่ได้แก้อยู่ในรายการ = ลืม `git pull`** → กด **Abort** แล้วกลับไปข้อ 1
4. **แก้โค้ดใน VS Code** → เซฟ (Rojo ส่งเข้า Studio ทันที) → กด Play ทดสอบใน Studio
5. **จดลง CHANGELOG** ในหัวข้อ 6 ของ [`_ARCHITECTURE.luau`](src/ReplicatedStorage/_ARCHITECTURE.luau) ว่าแก้อะไร
6. **เสร็จแต่ละเรื่อง ส่งขึ้น GitHub ทันที** (อย่าเก็บไว้ข้ามวัน)

   ```powershell
   git add .
   git commit -m "อธิบายสั้นๆ ว่าแก้อะไร"
   git pull
   git push
   ```

---

## กฎกันทับงานกัน

| ✅ แก้ใน Studio ได้ | ❌ ห้ามแก้ใน Studio (ต้องแก้ไฟล์ใน `src/`) |
|---|---|
| ทุกอย่างใน Workspace (แมพ, `Enemies/TrainingDummy` ฯลฯ) | ทุกสคริปต์ที่มีไฟล์อยู่ใน `src/` เช่น `SkillData`, `CombatServer`, `CombatClient`, `CameraScript`, `_ARCHITECTURE` |
| `StarterPlayer.StarterCharacter` | ถ้าแก้ใน Studio จะ**โดน Rojo เขียนทับ**ตอนใครก็ตามกด Connect หรือเซฟไฟล์นั้น |
| Lighting, Teams, SoundService ฯลฯ | ลบ → Rojo สร้างกลับมา, เปลี่ยนชื่อ → ได้ตัวซ้ำ 2 ตัว |

รายการเต็มอยู่ในหัวข้อ 3 ของ `_ARCHITECTURE.luau`

- แบ่งงานกันคนละไฟล์ ถ้าต้องแก้ไฟล์เดียวกันให้บอกกันก่อน
- จะสร้างสคริปต์ใหม่ ให้สร้างเป็นไฟล์ใน `src/` (ไม่ใช่กด Insert ใน Studio) จะได้ขึ้น GitHub ด้วย
  - `ชื่อ.server.luau` = Script, `ชื่อ.client.luau` = LocalScript, `ชื่อ.luau` = ModuleScript

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
