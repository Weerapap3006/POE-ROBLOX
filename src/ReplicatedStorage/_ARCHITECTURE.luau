--[[
==============================================================================
   PROJECT POE - GAME ARCHITECTURE REFERENCE
   (ไฟล์นี้ sync ผ่าน Rojo: src/ReplicatedStorage/_ARCHITECTURE.luau
    แก้ใน VS Code เท่านั้น ถ้าแก้ใน Studio จะโดน Rojo เขียนทับ)
==============================================================================

1. โครงสร้างโฟลเดอร์หลัก (EXPLORER STRUCTURE):
   - Workspace  [อยู่ใน game.rbxl เท่านั้น ไม่ sync ผ่าน Rojo]
     └── Enemies
          └── TrainingDummy (Model) : หุ่นซ้อมมือ R15 (HP 500, รีเลือดอัตโนมัติเมื่อตาย)

   - ReplicatedStorage (โซนกลาง: เห็นทั้ง Client และ Server)
     ├── _ARCHITECTURE (ModuleScript) : ไฟล์โน้ตสรุปโครงสร้างเกม (ไฟล์นี้)
     ├── Remotes
     │    └── CombatRemote (RemoteEvent) : ท่อส่งข้อมูลการโจมตีและผลดาเมจ
     └── Modules
          └── SkillData (ModuleScript) : ตารางเก็บค่า Cooldown, Damage, Crit, HitboxSize

   - ServerScriptService (โซน Server: ปลอดภัย 100% กันโปรโกง)
     └── CombatServer (Script) : ตรวจ Cooldown จริง, สร้าง Hitbox, คำนวณดาเมจ, ลดเลือดศัตรู

   - StarterPlayer (ตั้งค่าตัวละครและสคริปต์ฝั่งผู้เล่น)
     ├── StarterCharacter (Model) : หุ่นพื้นฐาน R15 Anime Base + CelShadeOutline (Highlight)
     │                               [อยู่ใน game.rbxl เท่านั้น ไม่ sync ผ่าน Rojo]
     └── StarterPlayerScripts
          ├── CameraScript (LocalScript) : ล็อกกล้อง 2.5D Isometric + ซูมด้วยลูกกลิ้ง
          └── CombatClient (LocalScript) : หันหน้าตามเมาส์, รับคลิกซ้าย, เล่น VFX, เลขดาเมจเด้ง

------------------------------------------------------------------------------
2. อยากแก้ค่าอะไร ให้ไปที่ไฟล์ไหน? (QUICK EDIT GUIDE):
   - แก้มุมกล้อง / ความเร็วกล้อง / ระยะซูม   --> StarterPlayerScripts.CameraScript
   - แก้ความแรงสกิล / คูลดาวน์ / ระยะฟัน     --> ReplicatedStorage.Modules.SkillData
   - แก้สีเอฟเฟกต์ / ขนาดตัวเลขดาเมจ        --> StarterPlayerScripts.CombatClient
   - แก้สูตรคำนวณดาเมจ / ระบบเช็ค Hitbox    --> ServerScriptService.CombatServer
   - แก้สีผิวหุ่นเริ่มต้น / เส้นขอบการ์ตูน     --> StarterPlayer.StarterCharacter (แก้ใน Studio)

------------------------------------------------------------------------------
3. ⚠ คำเตือนสำหรับเพื่อน: ROJO จะเขียนทับอะไรบ้าง? (ROJO SYNC RULES):
   [ห้ามแก้ใน Studio] มีไฟล์ใน src/ -> Rojo เขียนทับเสมอ ต้องแก้ที่ไฟล์เท่านั้น
   - ReplicatedStorage._ARCHITECTURE              --> src/ReplicatedStorage/_ARCHITECTURE.luau
   - ReplicatedStorage.Modules.SkillData          --> src/ReplicatedStorage/Modules/SkillData.luau
   - ReplicatedStorage.Remotes.CombatRemote       --> src/ReplicatedStorage/Remotes/CombatRemote.model.json
   - ServerScriptService.CombatServer             --> src/ServerScriptService/CombatServer.server.luau
   - StarterPlayerScripts.CameraScript            --> src/StarterPlayer/StarterPlayerScripts/CameraScript.client.luau
   - StarterPlayerScripts.CombatClient            --> src/StarterPlayer/StarterPlayerScripts/CombatClient.client.luau

   จังหวะที่โดนทับ:
   - ตอนกด Connect ใน Rojo: Studio ถูกทำให้ตรงกับไฟล์ทั้งหมด
     (Rojo จะโชว์รายการที่จะเปลี่ยนก่อน ถ้าเห็นงานที่ยังไม่ได้ย้ายลงไฟล์ ให้กด Abort)
   - ตอนเซฟไฟล์ใน VS Code ระหว่าง Connect อยู่: สคริปต์ตัวนั้นถูกทับทันที
   - ลบสคริปต์พวกนี้ใน Studio -> Rojo สร้างกลับมาใหม่
   - เปลี่ยนชื่อใน Studio -> ได้ตัวซ้ำ 2 ตัว (ตัวชื่อเดิมจาก Rojo + ตัวที่เปลี่ยนชื่อ)

   [แก้ใน Studio ได้] ไม่มีไฟล์ใน src/ -> Rojo ไม่ยุ่ง
   - Workspace ทั้งหมด (Enemies/TrainingDummy, Script1, SpawnLocation, Baseplate, Terrain)
   - StarterPlayer.StarterCharacter
   - Lighting, Teams, SoundService และ service อื่นที่ไม่อยู่ใน default.project.json
   - ของที่สร้างใหม่ใน StarterGui, StarterPack, ServerStorage, ReplicatedFirst,
     StarterCharacterScripts (โฟลเดอร์ใน src/ ยังว่าง)
   * ของกลุ่มนี้ไม่ได้ถูกเก็บเป็นไฟล์: ถ้า game.rbxl หาย/พัง ก็หายด้วย
   * ถ้าวันหลังมีไฟล์ชื่อเดียวกันเพิ่มใน src/ ของใน Studio จะโดนทับ

------------------------------------------------------------------------------
4. วิธีทำงานร่วมกัน 2 คน (TEAM WORKFLOW: Team Create + Git + Rojo):
   ของจริงอยู่ที่ไหน:
   - โค้ด (ทุกอย่างใน src/)              --> GitHub repo (แก้ใน VS Code, Rojo sync เข้า Studio)
   - แมพ / โมเดล / StarterCharacter     --> Team Create place (แก้ใน Studio ได้เลย)
   - game.rbxl ไม่ขึ้น git (.gitignore) เพราะแมพอยู่ใน Team Create แล้ว

   ทุกครั้งที่เริ่มทำงาน:
   1. git pull ก่อนเสมอ (เอาโค้ดล่าสุดของเพื่อนมา)
   2. เปิด Team Create -> Connect Rojo
      ดูรายการที่ Rojo จะเปลี่ยน: ถ้ามีสคริปต์ที่เราไม่ได้แก้ = ลืม pull -> กด Abort แล้ว pull ก่อน
   3. แก้โค้ดใน VS Code -> เซฟ -> ทดสอบใน Studio
   4. เสร็จแต่ละเรื่อง -> git commit + git push ทันที (อย่าค้างข้ามวัน)

   กันทับกัน:
   - แบ่งงานคนละไฟล์ ถ้าต้องแก้ไฟล์เดียวกันให้บอกกันก่อน
   - git แจ้ง conflict = แก้บรรทัดเดียวกัน -> เปิดใน VS Code เลือกว่าจะเก็บของใคร/เก็บทั้งคู่
   - CHANGELOG ข้างล่างจะ conflict บ่อย (เพิ่มบรรทัดบนสุดพร้อมกัน) -> เก็บไว้ทั้งสองบรรทัด
   - ห้ามแก้สคริปต์ในข้อ 3 ใน Studio แม้จะเปิด Team Create อยู่

------------------------------------------------------------------------------
5. ปัญหาที่รู้แล้ว ยังไม่ได้แก้ (KNOWN ISSUES):
   - CombatClient.playSlashVFX: ท่าเหวี่ยงแขน/บิดเอวตั้ง Motor6D.Transform ครั้งเดียว
     แต่ Animator เขียนทับทุกเฟรม ทำให้แทบมองไม่เห็นท่าฟัน (VFX เสี้ยวพระจันทร์ยังขึ้นปกติ)

------------------------------------------------------------------------------
6. บันทึกการแก้ไข (CHANGELOG) - ใหม่สุดอยู่บน:
   [2026-10-29]
   - Git: เริ่มใช้ repo https://github.com/Weerapap3006/POE-ROBLOX (branch main)
   - ใส่ .gitkeep ในโฟลเดอร์ว่างใน src/ (git ไม่เก็บโฟลเดอร์ว่าง ถ้าไม่มี
     เครื่องเพื่อนที่ clone ไปจะไม่มีโฟลเดอร์) + default.project.json ให้ Rojo ข้ามไฟล์ .gitkeep
   - _ARCHITECTURE: เพิ่มหัวข้อ 4 TEAM WORKFLOW (Team Create + Git + Rojo)
   - .gitignore: ไม่เอาไฟล์ place (*.rbxl, *.rbxlx) ขึ้น git
   - _ARCHITECTURE: เพิ่มหัวข้อ 3 คำเตือนสำหรับเพื่อน (ROJO SYNC RULES)
     ว่าอะไรแก้ใน Studio ได้ อะไรจะโดน Rojo เขียนทับ
   - SkillData.BasicSlash: สลับ MinDamage/MaxDamage ที่กลับด้านกัน (50/26 -> 26/50)
     เดิม math.random(50, 26) error ทุกครั้งที่ฟันโดน ทำให้ศัตรูไม่เสียเลือดเลย
   - _ARCHITECTURE: ย้ายมาอยู่ในไฟล์ Rojo (src/ReplicatedStorage/_ARCHITECTURE.luau)
     + เพิ่มหัวข้อ KNOWN ISSUES และ CHANGELOG
==============================================================================
]]

local ArchitectureInfo = {
	ProjectName = "Project poe",
	Style = "2.5D Isometric Anime Cel-Shaded ARPG",
}

return ArchitectureInfo
