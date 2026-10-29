--[[
================================================================================
   PROJECT POE - GAME ARCHITECTURE REFERENCE [โน้ตของ WEE / Weerapap3006]
   (เอกสารฉบับเต็มพร้อมแผนผังอยู่ที่ไฟล์ d:\roblox_poe\ARCHITECTURE.md)
================================================================================

1. โครงสร้างโฟลเดอร์หลัก (EXPLORER STRUCTURE):
   - Workspace
     ├── Enemies
     │   └── TrainingDummy (Model) : หุ่นซ้อมมือ R15 (HP 500, รีเลือดอัตโนมัติเมื่อตาย)
     ├── DungeonMap (Folder) : โซน Lobby + ประตูวาร์ปเข้าด่าน/กลับเมือง + โครงสร้างด่าน
     └── EnemySpawns (Folder) : จุดเกิดมอนสเตอร์ในด่าน (Grunt 10 + 10 ตัว, Brute 1 ตัว)

   - ReplicatedStorage (โซนกลาง: เห็นทั้ง Client และ Server)
     ├── _ARCHITECTURE WEE (ModuleScript) : ไฟล์โน้ตสรุปโครงสร้างและ CHANGELOG ของ WEE
     ├── Remotes
     │   ├── CombatRemote (RemoteEvent) : ท่อส่งข้อมูลการโจมตีและผลลัพธ์ดาเมจ
     │   └── TeleportRemote (RemoteEvent) : ท่อส่งคำขอวาร์ปกลับ Lobby จากหน้าต่างตั้งค่า
     └── Modules
         └── SkillData (ModuleScript) : ตารางเก็บค่า Cooldown, Damage, Crit, HitboxSize

   - ServerScriptService (โซน Server: ปลอดภัย 100% กันโปรโกง)
     └── CombatServer (Script) : ตรวจ Cooldown จริง, สร้าง Hitbox, คำนวณดาเมจ, ลดเลือดศัตรู

   - StarterPlayer (ตั้งค่าตัวละครและสคริปต์ฝั่งผู้เล่น)
     ├── StarterCharacter (Model) : หุ่นพื้นฐาน R15 Anime Base + CelShadeOutline (Highlight)
     └── StarterPlayerScripts
         ├── CameraScript (LocalScript) : ล็อกกล้อง 2.5D Isometric + ซูมเข้าออกสมูท
         ├── CombatClient (LocalScript) : หันหน้าตามเมาส์, รับคลิกซ้าย, เล่น VFX, เลขดาเมจเด้ง
         └── MinimapClient (LocalScript) : มินิแมพมุมขวาบน + กด M ขยายกลางจอ + ปุ่มตั้งค่า ⚙️ (กด P)

--------------------------------------------------------------------------------
2. อยากแก้ค่าอะไร ให้ไปที่ไฟล์ไหน? (QUICK EDIT GUIDE):
   - แก้มุมกล้อง / ความเร็วกล้อง / ระยะซูม  --> StarterPlayerScripts.CameraScript
   - แก้ความแรงสกิล / คูลดาวน์ / ระยะฟัน   --> ReplicatedStorage.Modules.SkillData
   - แก้สีคลื่นดาบ / ขนาดตัวเลขดาเมจเด้ง   --> StarterPlayerScripts.CombatClient
   - แก้ขนาดมินิแมพ / สีจุด / หน้าต่างตั้งค่า  --> StarterPlayerScripts.MinimapClient
   - แก้สูตรคำนวณดาเมจ / ระบบเช็ค Hitbox --> ServerScriptService.CombatServer
   - แก้สีผิวหุ่นเริ่มต้น / เส้นขอบการ์ตูน    --> StarterPlayer.StarterCharacter

--------------------------------------------------------------------------------
3. บันทึกการแก้ไข (CHANGELOG ของ WEE) - ใหม่สุดอยู่บน:
   [2026-10-30]
   - MinimapClient / TeleportRemote / EnemyService:
     + เพิ่มปุ่มตั้งค่า ⚙️ ข้างมินิแมพมุมขวาบน (หรือกดปุ่มลัด P) และปรับข้อความ UI เป็นภาษาอังกฤษ
     + ออกแบบหน้าต่าง Settings แบบหน้าเมนูหลัก (Main Menu) ที่ต้องกดเลือกหมวดก่อนเข้าไปปรับค่า:
       1. ปุ่ม "Map Settings >": กดเข้าไปจะเจอหน้าตั้งค่าแผนที่พร้อมปุ่ม "< Back" และหลอดเลื่อน (Sliders) สำหรับลากปรับขนาด Corner Map, Overlay Map [M], ระยะเรดาร์ และความทึบพื้นหลังแบบละเอียด
       2. ปุ่ม "Other Settings >": หน้าหมวดหมู่สำรองพร้อมปุ่ม "< Back" เตรียมไว้สำหรับใส่ตั้งค่าเพิ่มเติมในอนาคต
       3. ปุ่ม "Return to Lobby": วาร์ปกลับโซนปลอดภัย (Lobby) ทันทีพร้อมรีเลือดเต็ม (ผ่าน TeleportRemote)
   - InventoryClient / MinimapClient:
     + เปลี่ยนปุ่มเปิดกระเป๋าเป็น B (แทน I ที่ชนกับปุ่มซูมกล้อง Roblox) และปุ่มขยายแผนที่เป็น M (แทน Tab ที่ชนกับ Leaderboard)
     + เช็ก UserInputService:GetFocusedTextBox() == nil เพื่อให้กดปุ่ม B, M, P ติดเสมอโดยไม่โดนระบบ Roblox บล็อก
   - MinimapClient (src/StarterPlayer/StarterPlayerScripts/MinimapClient.client.luau):
     + เพิ่มระบบมินิแมพมุมขวาบน และกดปุ่ม M (หรือคลิกที่แมพ) เพื่อสลับขยายเป็นแผนที่โปร่งใสกลางจอแบบ PoE
     + จุดตัวเราเป็นสีขาวพร้อมเข็มชี้ทิศหน้า, จุดมอนสเตอร์สีแดง, จุดบอสสีส้มทอง, ประตูวาร์ป และแท่งกำแพงด่าน
     + แสดงตัวนับจำนวนศัตรูที่เหลืออยู่ในด่านมุมขวาล่างของมินิแมพ
   [2026-10-29]
   - EnemyService + DungeonMap:
     + ปรับให้มอนสเตอร์ในด่านตายแล้วตายเลย (ไม่เกิดใหม่เองตามเวลา RespawnTime)
     + เพิ่มฟังก์ชัน EnemyService.resetDungeon() และระบบประตูวาร์ป (LobbyDungeonPortal / DungeonReturnPortal)
       เมื่อกดเข้าประตูวาร์ปจาก Lobby จะล้างและเสกมอนสเตอร์ทั้งด่านใหม่ทั้งหมด แล้ววาร์ปไปจุดเริ่มด่าน
     + สร้างฉาก DungeonMap และ EnemySpawns ใน Workspace (โซน Lobby + ด่านทางยาว: Grunt 10 ตัว -> Grunt 10 ตัว -> บอส Brute 1 ตัว)
================================================================================
]]

local ArchitectureInfo = {
	ProjectName = "Project poe",
	Style = "2.5D Isometric Anime Cel-Shaded ARPG",
}

return ArchitectureInfo
