--[[
==============================================================================
   PROJECT POE - GAME ARCHITECTURE REFERENCE  [โน้ตของ DON / chwwy]
   (ไฟล์นี้ sync ผ่าน Rojo: src/ReplicatedStorage/_ARCHITECTURE DON.luau
    แก้ใน VS Code เท่านั้น ถ้าแก้ใน Studio จะโดน Rojo เขียนทับ)
   (โน้ตของเพื่อน -> _ARCHITECTURE WEE / Weerapap3006: ไม่แก้ของกันและกัน)
   (อธิบายแต่ละระบบแบบละเอียด + flow การต่อสู้ -> ARCHITECTURE.md ที่ root ของ repo)
==============================================================================

1. โครงสร้างโฟลเดอร์หลัก (EXPLORER STRUCTURE):
   - Workspace  [แมพ: แก้ใน Studio, อยู่ใน Team Create, ไม่ขึ้น GitHub]
     └── Enemies
          └── TrainingDummy (Model) : หุ่นซ้อมมือ R15 (HP 500, รีเลือดอัตโนมัติเมื่อตาย)

   - ReplicatedStorage (โซนกลาง: เห็นทั้ง Client และ Server)
     ├── _ARCHITECTURE DON (ModuleScript) : โน้ตของ DON / chwwy (ไฟล์นี้)
     ├── _ARCHITECTURE WEE (ModuleScript) : โน้ตของ WEE / Weerapap3006
     ├── Remotes
     │    └── CombatRemote (RemoteEvent) : ท่อส่งข้อมูลการโจมตีและผลดาเมจ
     └── Modules
          └── SkillData (ModuleScript) : ตารางเก็บค่า Cooldown, Damage, Crit, HitboxSize

   - ServerScriptService (โซน Server: ปลอดภัย 100% กันโปรโกง)
     └── CombatServer (Script) : ตรวจ Cooldown จริง, สร้าง Hitbox, คำนวณดาเมจ, ลดเลือดศัตรู

   - StarterPlayer (ตั้งค่าตัวละครและสคริปต์ฝั่งผู้เล่น)
     ├── StarterCharacter (Model) : หุ่นพื้นฐาน R15 Anime Base + CelShadeOutline (Highlight)
     │                               [แมพ: แก้ใน Studio, อยู่ใน Team Create, ไม่ขึ้น GitHub]
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
3. ⚠ แยกงาน: แมพ = Studio / โค้ด = VS Code + GitHub (MAP vs CODE):
   [โค้ด: ห้ามแก้ใน Studio] มีไฟล์ใน src/ -> Rojo เขียนทับเสมอ ต้องแก้ที่ไฟล์แล้ว push ขึ้น GitHub
   - ReplicatedStorage._ARCHITECTURE DON          --> src/ReplicatedStorage/_ARCHITECTURE DON.luau
   - ReplicatedStorage._ARCHITECTURE WEE          --> src/ReplicatedStorage/_ARCHITECTURE WEE.luau
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

   [แมพ: แก้ใน Studio] ไม่มีไฟล์ใน src/ -> Rojo ไม่ยุ่ง, ไม่ขึ้น GitHub
   - Workspace ทั้งหมด (Enemies/TrainingDummy, SpawnLocation, Baseplate, Terrain)
   - StarterPlayer.StarterCharacter
   - Lighting, Teams, SoundService และ service อื่นที่ไม่อยู่ใน default.project.json
   - หน้าตา UI (ScreenGui/Frame/ปุ่ม) ใน StarterGui
   * แมพเก็บอยู่ใน Team Create เท่านั้น (ย้อนเวอร์ชันได้ที่ File -> Version History)
   * ถ้าวันหลังมีไฟล์ชื่อเดียวกันเพิ่มใน src/ ของใน Studio จะโดนทับ

   ของใหม่ใส่ที่ไหน:
   - สคริปต์ทุกตัวที่เราเขียนเอง -> สร้างเป็นไฟล์ใน src/ เสมอ (ห้ามกด Insert Script ใน Studio)
       ฝั่ง server      --> src/ServerScriptService/ชื่อ.server.luau
       ฝั่ง client      --> src/StarterPlayer/StarterPlayerScripts/ชื่อ.client.luau
       ใช้ร่วมกัน       --> src/ReplicatedStorage/Modules/ชื่อ.luau
       (สคริปต์ของปุ่ม UI ก็ใส่ฝั่ง client แล้วไปหา UI ผ่าน PlayerGui)
   - Part / Model / Terrain / แสง / เสียง / หน้าตา UI -> สร้างใน Studio
   - ข้อยกเว้น: LocalScript "Animate" ใน TrainingDummy และ StarterCharacter
     เป็นสคริปต์ท่าเดินมาตรฐานที่ติดมากับหุ่น R15 -> ปล่อยไว้ในโมเดล ไม่ต้องย้าย

   สิ่งที่โค้ดต้องการจากแมพ (แก้แมพแล้วอย่าทำข้อพวกนี้พัง):
   - ศัตรู = Model ที่มี Humanoid + HumanoidRootPart
     ชิ้นส่วนตัวต้องอยู่ใน Model เดียวกับ Humanoid (ถ้าซ้อน Model ข้างใน hitbox จะหา Humanoid ไม่เจอ)
   - ใส่ Highlight ในตัวศัตรู -> ถึงจะกระพริบขาวตอนโดนฟัน
   - ชื่อ "TrainingDummy" -> เลือดเต็มคืนเองหลังตาย 1.2 วิ (เปลี่ยนชื่อ = ไม่รีเลือด)
   - StarterCharacter ต้องมี HumanoidRootPart (กล้องตาม) และเป็น R15
     (RightUpperArm.RightShoulder, UpperTorso.Waist) ไม่งั้นท่าฟันไม่ขยับ
   - ห้ามสร้าง Remotes / Modules ใน Studio เอง (มาจากโค้ดทั้งหมด)

------------------------------------------------------------------------------
4. วิธีทำงานร่วมกัน 2 คน (TEAM WORKFLOW: Team Create + Git + Rojo):
   วิธีลงโปรแกรม/ตั้งค่าครั้งแรกสำหรับคนใหม่ --> README.md (หน้าแรกของ repo บน GitHub)

   ของจริงอยู่ที่ไหน:
   - โค้ด (ทุกอย่างใน src/)              --> GitHub repo (แก้ใน VS Code, Rojo sync เข้า Studio)
   - แมพ / โมเดล / StarterCharacter     --> Team Create place (แก้ใน Studio ได้เลย)
   - game.rbxl ไม่ขึ้น git (.gitignore) เพราะแมพอยู่ใน Team Create แล้ว

   Rojo ใน Team Create ให้ Connect ได้ทีละคน (__Rojo_SessionLock ใน ServerStorage)
   เลยแบ่งเป็น 3 งาน (ขั้นตอนเต็มอยู่ใน README):
   - แต่งแมพ      --> Team Create, ไม่ใช้ Rojo
   - เขียน/เทสโค้ด --> place สำเนาในเครื่องตัวเอง (game.rbxl ที่ Save to File As จาก Team Create)
                     git pull -> rojo serve -> เปิด game.rbxl -> Connect -> แก้ -> เทส -> commit + push
                     ห้าม Publish to Roblox จาก game.rbxl (แมพเก่าจะทับ Team Create)
   - ส่งโค้ดเข้าเกมจริง --> ทีละคน: git pull -> Connect เข้า Team Create -> เช็กรายการ -> Disconnect ทันที

   กันทับกัน:
   - แบ่งงานคนละไฟล์ ถ้าต้องแก้ไฟล์เดียวกันให้บอกกันก่อน
   - git แจ้ง conflict = แก้บรรทัดเดียวกัน -> เปิดใน VS Code เลือกว่าจะเก็บของใคร/เก็บทั้งคู่
   - แต่ละคนจด CHANGELOG ในโน้ตของตัวเอง (DON / WEE) -> ไม่ conflict กัน, ห้ามแก้โน้ตของอีกคน
   - ห้ามแก้สคริปต์ในข้อ 3 ใน Studio แม้จะเปิด Team Create อยู่

------------------------------------------------------------------------------
5. ปัญหาที่รู้แล้ว ยังไม่ได้แก้ (KNOWN ISSUES):
   - Workspace.Script1: สคริปต์ว่าง 3 ตัว (print "Hello world!") ปนอยู่ในแมพ -> ลบทิ้งใน Studio

------------------------------------------------------------------------------
6. บันทึกการแก้ไข (CHANGELOG) - ใหม่สุดอยู่บน:
   [2026-10-29]
   - ARCHITECTURE.md: อัปเดตให้ตรงโค้ด -> _ARCHITECTURE DON/WEE, ท่าฟัน PreSimulation + จุดปรับแก้ของ
     CombatClient, ReplicateSlash, MAX_ZOOM_DISTANCE 90 -> 50 (โค้ดเป็น 50 มาตั้งแต่แรก)
   - CombatClient: แก้ท่าฟันที่มองไม่เห็น -> ใส่ท่าเหวี่ยงแขน/บิดเอวซ้ำทุกเฟรมใน RunService.PreSimulation
     (รันหลัง Animator) ซ้อนบนท่าเดิน/ยืน, เหวี่ยงออกแล้วกลับใน 0.18 วิ (SWING_DURATION)
   - แยกโน้ตคนละไฟล์: _ARCHITECTURE -> _ARCHITECTURE DON (chwwy, ไฟล์นี้)
     + เพิ่ม _ARCHITECTURE WEE (Weerapap3006) เข้า src/ ด้วยเนื้อหาเดิมจาก Studio ทุกตัวอักษร
     -> ทั้งสองไฟล์ขึ้น GitHub แล้ว, Rojo จะไม่สร้าง _ARCHITECTURE ตัวเก่ากลับมาอีก
   - TEAM WORKFLOW (README + หัวข้อ 4): เปลี่ยนเป็นเทสโค้ดใน place สำเนา (game.rbxl)
     เพราะ Rojo ใน Team Create ให้ Connect ได้ทีละคน -> ส่งโค้ดเข้า Team Create ทีละคนแล้ว Disconnect
   - README + หัวไฟล์นี้: ลิงก์ไป ARCHITECTURE.md (เอกสารระบบแบบละเอียด ที่ Weerapap3006 เพิ่มมา)
   - _ARCHITECTURE หัวข้อ 3: เปลี่ยนเป็น "แยกงาน แมพ = Studio / โค้ด = VS Code + GitHub"
     + เพิ่ม "ของใหม่ใส่ที่ไหน" และ "สิ่งที่โค้ดต้องการจากแมพ"
     + KNOWN ISSUES: Workspace.Script1 (สคริปต์ว่างในแมพ) ต้องลบใน Studio
   - .gitignore: ไม่เอา settings ส่วนตัวของ Claude Code (.claude/settings.local.json) ขึ้น git
   - README.md: เขียนใหม่เป็นคู่มือเพื่อน (ลง Git/VS Code/Rojo 7.7.1, clone, ขั้นตอนทุกวัน,
     กฎกันทับงาน, ปัญหาที่เจอบ่อย)
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
