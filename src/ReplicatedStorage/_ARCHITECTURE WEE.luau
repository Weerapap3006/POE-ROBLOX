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
     │   └── CombatRemote (RemoteEvent) : ท่อส่งข้อมูลการโจมตีและผลลัพธ์ดาเมจ
     └── Modules
         └── SkillData (ModuleScript) : ตารางเก็บค่า Cooldown, Damage, Crit, HitboxSize

   - ServerScriptService (โซน Server: ปลอดภัย 100% กันโปรโกง)
     └── CombatServer (Script) : ตรวจ Cooldown จริง, สร้าง Hitbox, คำนวณดาเมจ, ลดเลือดศัตรู

   - StarterPlayer (ตั้งค่าตัวละครและสคริปต์ฝั่งผู้เล่น)
     ├── StarterCharacter (Model) : หุ่นพื้นฐาน R15 Anime Base + CelShadeOutline (Highlight)
     └── StarterPlayerScripts
         ├── CameraScript (LocalScript) : ล็อกกล้อง 2.5D Isometric + ซูมเข้าออกสมูท
         └── CombatClient (LocalScript) : หันหน้าตามเมาส์, รับคลิกซ้าย, เล่น VFX, เลขดาเมจเด้ง

--------------------------------------------------------------------------------
2. อยากแก้ค่าอะไร ให้ไปที่ไฟล์ไหน? (QUICK EDIT GUIDE):
   - แก้มุมกล้อง / ความเร็วกล้อง / ระยะซูม  --> StarterPlayerScripts.CameraScript
   - แก้ความแรงสกิล / คูลดาวน์ / ระยะฟัน   --> ReplicatedStorage.Modules.SkillData
   - แก้สีคลื่นดาบ / ขนาดตัวเลขดาเมจเด้ง   --> StarterPlayerScripts.CombatClient
   - แก้สูตรคำนวณดาเมจ / ระบบเช็ค Hitbox --> ServerScriptService.CombatServer
   - แก้สีผิวหุ่นเริ่มต้น / เส้นขอบการ์ตูน    --> StarterPlayer.StarterCharacter

--------------------------------------------------------------------------------
3. บันทึกการแก้ไข (CHANGELOG ของ WEE) - ใหม่สุดอยู่บน:
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
