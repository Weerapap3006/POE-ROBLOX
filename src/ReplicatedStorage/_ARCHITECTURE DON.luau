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
     ├── DungeonMap : Lobby (โซนปลอดภัย), กำแพงด่าน, ประตูวาร์ป LobbyDungeonPortal / DungeonReturnPortal
     ├── Enemies : ศัตรูทั้งหมด (EnemyService สร้างตอนเริ่มเกม / ตอนรีเซ็ตด่าน)
     │    └── TrainingDummy (Model) : หุ่นซ้อมมือ R15 (HP 500, รีเลือดเอง, ไม่ให้ EXP/ของ)
     ├── EnemySpawns : Part จุดเกิดศัตรู ชื่อ Grunt / Brute (ตอนนี้ Grunt 20 + Brute 1, ไม่มี = ใช้ด่านเริ่มต้น)
     └── Drops : ของที่ดรอปบนพื้น (โค้ดสร้างตอนเล่น)

   - ReplicatedStorage (โซนกลาง: เห็นทั้ง Client และ Server)
     ├── _ARCHITECTURE DON (ModuleScript) : โน้ตของ DON / chwwy (ไฟล์นี้)
     ├── _ARCHITECTURE WEE (ModuleScript) : โน้ตของ WEE / Weerapap3006
     ├── Remotes
     │    ├── CombatRemote (RemoteEvent) : ใช้สกิล, เลขดาเมจ, ท่าโจมตีศัตรู, "!" ตอนศัตรูเห็นเรา
     │    ├── DodgeRemote (RemoteEvent) : กลิ้งหลบ (ขอช่วงอมตะจาก Server)
     │    ├── FlaskRemote (RemoteEvent) : ดื่มขวดยาเลือด/มานา (Server หักจำนวนแล้วค่อยๆ ฟื้น)
     │    ├── InventoryRemote (RemoteEvent) : สวมใส่/ถอด/ทิ้งของ + ข้อมูลกระเป๋า
     │    ├── NotifyRemote (RemoteEvent) : ข้อความกลางจอ
     │    └── TeleportRemote (RemoteEvent) : ขอวาร์ปกลับ Lobby จากหน้าตั้งค่า
     └── Modules
          ├── SkillData : ค่าสกิล Slash / Spin Slash (รวมมานาที่ใช้ ManaCost)
          ├── EnemyData : ค่าศัตรู Stone Grunt / บอส Stone Guardian (เลือด, ท่าตี + ธาตุ, EXP, ดรอป)
          ├── Elements : ธาตุ ไฟ/น้ำแข็ง/สายฟ้า, สี, ตัวเลขสถานะผิดปกติ, ค่าต้านทานสูงสุด
          ├── RuneData : รูนสลักหิน 6 แบบ (ชื่อ, คำอธิบาย, ใส่สกิลไหนได้, ตัวเลขผล)
          ├── ItemData : ไอเทม, affix (รวม ES, ดาเมจธาตุ, ค่าต้านทาน), ความหายาก, ช่องสวมใส่ 9 ช่อง
          ├── PlayerStats : เลือด/มานา/ดาเมจต่อเลเวล, EXP ที่ต้องใช้, กลิ้งหลบ (DODGE_*),
          │                 มานา (MANA_*), Energy Shield (ENERGY_SHIELD_*), ขวดยา (FLASKS, FLASK_*)
          └── Ui : สี/ฟอนต์/ตัวช่วยสร้าง UI

   - ServerScriptService (โซน Server: ปลอดภัย 100% กันโปรโกง)
     ├── CombatServer (Script) : ตรวจ Cooldown + หักมานาจริง, สร้าง Hitbox, คำนวณดาเมจ, กลิ้งหลบ
     ├── EnemyServer (Script) : เริ่ม EnemyService
     ├── PlayerDataServer (Script) : เริ่ม PlayerData
     └── PlayerResourcesServer (Script) : เริ่ม PlayerResources

   - ServerStorage.Modules (โมดูลฝั่ง Server)
     ├── PlayerData : เลเวล, EXP, กระเป๋า, เซฟ/โหลด DataStore
     ├── PlayerResources : มานา, Energy Shield (รับดาเมจก่อนเลือด), ขวดยาเลือด/มานา (ไม่เซฟ)
     ├── Ailments : ติดไฟ / ช้า / แข็ง / ช็อต จากดาเมจธาตุ (ใช้ได้ทั้งศัตรูและผู้เล่น)
     ├── EnemyService : เกิดศัตรู, AI, ตาย -> EXP + ขวดยา + ดรอป, รีเซ็ตด่าน + ประตูวาร์ป (เติมทุกอย่างเต็ม)
     └── Loot : สุ่มไอเทม, วางของบนพื้นให้เก็บ

   - StarterPlayer (ตั้งค่าตัวละครและสคริปต์ฝั่งผู้เล่น)
     ├── StarterCharacter (Model) : หุ่นพื้นฐาน R15 Anime Base + CelShadeOutline (Highlight)
     │                               [แมพ: แก้ใน Studio, อยู่ใน Team Create, ไม่ขึ้น GitHub]
     └── StarterPlayerScripts
          ├── CameraScript (LocalScript) : ล็อกกล้อง 2.5D Isometric + ซูมด้วยลูกกลิ้ง
          ├── CombatClient (LocalScript) : เล็ง, กดสกิล, กลิ้งหลบ (Space, ไม่มีกระโดด), ขวดยาเลือด/มานา
          │                                (กด 1 / 2), แถบสกิล, VFX, เตือนท่าศัตรู + "!", เลขดาเมจ
          ├── HudClient (LocalScript) : แถบ ES/เลือด/มานา/EXP, แถบเลือดศัตรู/บอส, ข้อความ, หน้าจอตาย
          ├── InventoryClient (LocalScript) : หน้าต่างกระเป๋า (กด B)
          ├── EnemyVisualsClient (LocalScript) : ท่าเดินศัตรู + คุมจำนวน Highlight ไม่ให้เกิน 31
          └── MinimapClient (LocalScript) : มินิแมพ (กด M ขยายกลางจอ) + หน้าตั้งค่า (กด P, วาร์ปกลับ Lobby)

------------------------------------------------------------------------------
2. อยากแก้ค่าอะไร ให้ไปที่ไฟล์ไหน? (QUICK EDIT GUIDE):
   - แก้มุมกล้อง / ความเร็วกล้อง / ระยะซูม   --> StarterPlayerScripts.CameraScript
   - แก้ความแรงสกิล / คูลดาวน์ / ระยะฟัน     --> ReplicatedStorage.Modules.SkillData
   - แก้เลือด / ความเร็ว / ดาเมจ / ดรอปของศัตรู --> ReplicatedStorage.Modules.EnemyData
   - เพิ่มไอเทม / affix / ช่วงค่าที่สุ่ม / ช่องสวมใส่ --> ReplicatedStorage.Modules.ItemData
   - แก้เลือดเริ่มต้น / เลเวลอัป / EXP         --> ReplicatedStorage.Modules.PlayerStats
   - แก้ระยะ / คูลดาวน์ / ช่วงอมตะของกลิ้งหลบ  --> ReplicatedStorage.Modules.PlayerStats (DODGE_*)
     (ปุ่มกลิ้ง + ท่าตีลังกา: CombatClient DODGE_KEY, ROLL_DIP, ROLL_PIVOT)
   - แก้จำนวนครั้ง / ฟื้นเท่าไร / ได้คืนตอนฆ่าของขวดยา --> ReplicatedStorage.Modules.PlayerStats (FLASKS, FLASK_*)
     (ปุ่มขวดยา + สีน้ำ/ประกาย: CombatClient FLASK_SLOTS)
   - แก้มานาเริ่มต้น / ฟื้นมานา / ES ชาร์จช้าเร็ว --> ReplicatedStorage.Modules.PlayerStats (MANA_*, ENERGY_SHIELD_*)
     (มานาที่สกิลใช้: SkillData ManaCost, ค่า affix ES: ItemData Affixes)
   - แก้ไฟเผาแรงแค่ไหน / ช้า / แข็ง / ช็อต / ค่าต้านทานสูงสุด --> ReplicatedStorage.Modules.Elements
     (ธาตุของท่าศัตรู: EnemyData Attack.Element, ค่า affix ธาตุ/ค่าต้านทาน: ItemData Affixes)
   - แก้ผลของรูน / เพิ่มรูนใหม่              --> ReplicatedStorage.Modules.RuneData
     (จำนวนช่อง: SkillData Sockets, โอกาสดรอป: EnemyData Drops.RuneChance,
      ผลจริง: ServerScriptService.CombatServer, หน้าตา: CombatClient getSkillLook)
   - แก้สีเอฟเฟกต์ / ขนาดตัวเลขดาเมจ / ปุ่มสกิล --> StarterPlayerScripts.CombatClient
   - แก้สี UI ทั้งเกม                       --> ReplicatedStorage.Modules.Ui
   - แก้สูตรคำนวณดาเมจ / ระบบเช็ค Hitbox    --> ServerScriptService.CombatServer
   - แก้ AI ศัตรู / รูปร่างศัตรู / ด่านเริ่มต้น / ประตูวาร์ป --> ServerStorage.Modules.EnemyService
     (เลือดศัตรูเพิ่มตามจำนวนผู้เล่น: HEALTH_PER_EXTRA_PLAYER, หลบสิ่งกีดขวาง: PATH_*,
      รีเซ็ตด่าน: resetDungeon, ประตูวาร์ป + TeleportRemote: setupDungeonPortals,
      เวลายืนนิ่งตอนเห็นผู้เล่นครั้งแรก: ALERT_TIME, ระดับสายตา: EYE_HEIGHT)
   - แก้ท่าเดินศัตรู / จำนวนเส้นขอบที่โชว์     --> StarterPlayerScripts.EnemyVisualsClient
   - แก้ปุ่มเปิดกระเป๋า / ช่องสวมใส่บนจอ      --> StarterPlayerScripts.InventoryClient (TOGGLE_KEY, SLOT_LAYOUT)
     (คีย์ลัด: Shift + คลิก = สวม/ถอดทันที, ชี้แล้วกด X = ทิ้งทันที DISCARD_KEY)
   - แก้มินิแมพ / หน้าตั้งค่า / ปุ่ม M, P       --> StarterPlayerScripts.MinimapClient
   - แก้ขนาดกระเป๋า / ระบบเซฟ                --> ServerStorage.Modules.PlayerData
   - แก้สีผิวหุ่นเริ่มต้น / เส้นขอบการ์ตูน     --> StarterPlayer.StarterCharacter (แก้ใน Studio)

------------------------------------------------------------------------------
3. ⚠ แยกงาน: แมพ = Studio / โค้ด = VS Code + GitHub (MAP vs CODE):
   [โค้ด: ห้ามแก้ใน Studio] มีไฟล์ใน src/ -> Rojo เขียนทับเสมอ ต้องแก้ที่ไฟล์แล้ว push ขึ้น GitHub
   - ReplicatedStorage._ARCHITECTURE DON          --> src/ReplicatedStorage/_ARCHITECTURE DON.luau
   - ReplicatedStorage._ARCHITECTURE WEE          --> src/ReplicatedStorage/_ARCHITECTURE WEE.luau
   - ReplicatedStorage.Modules.*                  --> src/ReplicatedStorage/Modules/ชื่อ.luau
       (SkillData, EnemyData, Elements, RuneData, ItemData, PlayerStats, Ui)
   - ReplicatedStorage.Remotes.*                  --> src/ReplicatedStorage/Remotes/ชื่อ.model.json
       (CombatRemote, DodgeRemote, FlaskRemote, InventoryRemote, NotifyRemote, TeleportRemote)
   - ServerScriptService.*                        --> src/ServerScriptService/ชื่อ.server.luau
       (CombatServer, EnemyServer, PlayerDataServer, PlayerResourcesServer)
   - ServerStorage.Modules.*                      --> src/ServerStorage/Modules/ชื่อ.luau
       (PlayerData, PlayerResources, Ailments, EnemyService, Loot)
   - StarterPlayerScripts.*                       --> src/StarterPlayer/StarterPlayerScripts/ชื่อ.client.luau
       (CameraScript, CombatClient, HudClient, InventoryClient, EnemyVisualsClient, MinimapClient)

   จังหวะที่โดนทับ:
   - ตอนกด Connect ใน Rojo: Studio ถูกทำให้ตรงกับไฟล์ทั้งหมด
     (Rojo จะโชว์รายการที่จะเปลี่ยนก่อน ถ้าเห็นงานที่ยังไม่ได้ย้ายลงไฟล์ ให้กด Abort)
   - ตอนเซฟไฟล์ใน VS Code ระหว่าง Connect อยู่: สคริปต์ตัวนั้นถูกทับทันที
   - ลบสคริปต์พวกนี้ใน Studio -> Rojo สร้างกลับมาใหม่
   - เปลี่ยนชื่อใน Studio -> ได้ตัวซ้ำ 2 ตัว (ตัวชื่อเดิมจาก Rojo + ตัวที่เปลี่ยนชื่อ)

   [แมพ: แก้ใน Studio] ไม่มีไฟล์ใน src/ -> Rojo ไม่ยุ่ง, ไม่ขึ้น GitHub
   - Workspace ทั้งหมด (Enemies/TrainingDummy, DungeonMap, EnemySpawns, SpawnLocation, Baseplate, Terrain)
   - StarterPlayer.StarterCharacter
   - Lighting, Teams, SoundService และ service อื่นที่ไม่อยู่ใน default.project.json
   - หน้าตา UI (ScreenGui/Frame/ปุ่ม) ใน StarterGui
     (ตอนนี้ UI ทั้งหมดสร้างจากโค้ดใน HudClient / InventoryClient / CombatClient / MinimapClient
      StarterGui ยังว่าง -> อยากแก้หน้าตา UI ปัจจุบันต้องแก้ในโค้ด)
   * แมพเก็บอยู่ใน Team Create เท่านั้น (ย้อนเวอร์ชันได้ที่ File -> Version History)
   * ถ้าวันหลังมีไฟล์ชื่อเดียวกันเพิ่มใน src/ ของใน Studio จะโดนทับ

   ของใหม่ใส่ที่ไหน:
   - สคริปต์ทุกตัวที่เราเขียนเอง -> สร้างเป็นไฟล์ใน src/ เสมอ (ห้ามกด Insert Script ใน Studio)
       ฝั่ง server      --> src/ServerScriptService/ชื่อ.server.luau
       ฝั่ง client      --> src/StarterPlayer/StarterPlayerScripts/ชื่อ.client.luau
       ใช้ร่วมกัน       --> src/ReplicatedStorage/Modules/ชื่อ.luau
       โมดูลฝั่ง server --> src/ServerStorage/Modules/ชื่อ.luau (client มองไม่เห็น)
       (สคริปต์ของปุ่ม UI ก็ใส่ฝั่ง client แล้วไปหา UI ผ่าน PlayerGui)
   - Part / Model / Terrain / แสง / เสียง / หน้าตา UI -> สร้างใน Studio
   - ข้อยกเว้น: LocalScript "Animate" ใน TrainingDummy และ StarterCharacter
     เป็นสคริปต์ท่าเดินมาตรฐานที่ติดมากับหุ่น R15 -> ปล่อยไว้ในโมเดล ไม่ต้องย้าย

   สิ่งที่โค้ดต้องการจากแมพ (แก้แมพแล้วอย่าทำข้อพวกนี้พัง):
   - ศัตรู = Model ที่มี Humanoid + HumanoidRootPart
     ชิ้นส่วนตัวต้องอยู่ใน Model เดียวกับ Humanoid (ถ้าซ้อน Model ข้างใน hitbox จะหา Humanoid ไม่เจอ)
   - ใส่ Highlight ในตัวศัตรู -> ถึงจะกระพริบขาวตอนโดนฟัน
     EnemyVisualsClient เปิด/ปิด Highlight ทุกอันเอง (โชว์แค่ที่ใกล้สุด 27 อัน)
     อยากซ่อน Highlight ให้ลบทิ้ง อย่าใช้ Enabled = false
   - ชื่อ "TrainingDummy" -> เลือดเต็มคืนเองหลังตาย 1.2 วิ (เปลี่ยนชื่อ = ไม่รีเลือด)
   - StarterCharacter ต้องมี HumanoidRootPart (กล้องตาม) และเป็น R15
     (RightUpperArm.RightShoulder, UpperTorso.Waist) ไม่งั้นท่าฟันไม่ขยับ
     (LowerTorso.Root) ไม่งั้นท่ากลิ้งไม่ขยับ (ตัวยังพุ่งไปได้)
   - ผู้เล่นกระโดดไม่ได้ (Space = กลิ้งหลบ) -> ทุกจุดในแมพต้องเดินขึ้นได้ ห้ามมีขอบที่ต้องกระโดด
   - ศัตรูมองไม่ทะลุ Part ที่ CanCollide = true -> ผู้เล่นหลังกำแพงจะยังไม่โดนเห็น
   - ห้ามสร้าง Remotes / Modules ใน Studio เอง (มาจากโค้ดทั้งหมด)
   - ด่าน: ใส่ Part ใน Workspace.EnemySpawns ตรงจุดที่อยากให้ศัตรูเกิด
     ชื่อ Part = ชนิดศัตรูใน EnemyData (Grunt / Brute) หรือใส่ Attribute EnemyType
     ไม่มีโฟลเดอร์นี้ = โค้ดวางด่านเริ่มต้นรอบ SpawnLocation (ลูกสมุน 6 + บอส 1)
     เหนือ Part 10 studs ห้ามมีหลังคา (ศัตรูยิง Raycast หาพื้นจากตรงนั้น)
   - ประตูวาร์ป: ใน Workspace.DungeonMap ต้องมี LobbyDungeonPortal (รีเซ็ตด่าน + เข้าด่าน)
     และ DungeonReturnPortal (กลับ Lobby) ข้างในแต่ละบานมี ProximityPrompt ชื่อ PortalPrompt
     จุดเริ่มด่าน = Part ชื่อ DungeonEntranceSpawn, จุดกลับ Lobby = SpawnLocation ตัวแรกที่เจอ
     ไม่มีโฟลเดอร์ DungeonMap = ประตูวาร์ปและปุ่ม Return to Lobby ในหน้าตั้งค่าใช้ไม่ได้ทั้งคู่
     ข้อความป้ายประตู (TextLabel) + ObjectText/ActionText ของ PortalPrompt โค้ดตั้งทับตอนเริ่มเกม
     -> แก้ใน Studio ไม่มีผล ต้องแก้ใน EnemyService (setupDungeonPortals)
   - ศัตรูเดินอ้อมกำแพงได้ (PathfindingService) แต่กระโดดไม่ได้
     ทางที่ต้องกระโดดขึ้น = ศัตรูไปไม่ถึง, ทางเดินต้องกว้างพอให้บอส (~10 studs)
     ของตกแต่งที่ไม่อยากให้ขวางทาง -> ตั้ง CanCollide = false

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
   - เข้าประตูวาร์ปจาก Lobby = รีเซ็ตทั้งด่าน แม้มีเพื่อนเล่นอยู่ในด่าน
     (ศัตรูที่เพื่อนกำลังสู้จะหายแล้วเกิดใหม่หมด)
   - ศัตรูยังไม่มีท่าง้างตอนโจมตี (มีแค่ท่าเดิน), pathfinding ไม่กระโดด
   - ช่วงอมตะของการกลิ้งเริ่มตอน Server ได้รับ ไม่ใช่ตอนกด (ping สูง = โดนตีตอนเพิ่งกดได้)
   - ยังไม่มีศัตรูที่ตีเป็นน้ำแข็ง/สายฟ้า -> affix ต้านน้ำแข็ง/สายฟ้ายังไม่มีผล (มีแค่บอสตีไฟ)
   - บอสโดนแช่แข็งตอนง้าง = ทุบไม่ลง แต่วงแดงบน Client ยังเล่นจนจบ

------------------------------------------------------------------------------
6. บันทึกการแก้ไข (CHANGELOG) - ใหม่สุดอยู่บน:
   [2026-10-30]
   - เฟส 7 ข้อ 3: รูนสลักหิน (ระบบแต่งสกิล) [ยังไม่ได้เทสใน Studio]:
     + RuneData (ใหม่): Reach (+40% พื้นที่), Split (ฟันเพิ่มซ้ายขวา 35°, Slash เท่านั้น),
       Ember/Frost/Storm (กายภาพ 50% -> ไฟ/น้ำแข็ง/สายฟ้า), Detonation (ศพระเบิด 15% เลือดสูงสุด)
     + SkillData.Sockets: Slash 2, Spin Slash 3 / ใส่รูนชนิดเดียวกันซ้ำในสกิลเดียวไม่ได้
     + ItemData: ไอเทมรูนสร้างจาก RuneData (Slot "Rune", Rarity "Rune" สีส้ม), getRuneId
     + EnemyData Drops.RuneChance (Grunt 10%, บอส 100%) + Loot.rollRune, rollItem ไม่สุ่มรูน
     + PlayerData: profile.SkillRunes (เซฟลง DataStore, ล้างตอนโหลด), action Socket / Unsocket,
       Equip รูนไม่ได้, getSkillRunes, attribute SkillRunes_<skillId>
     + CombatServer: ผลรูนทั้ง 6 + แยก collectEnemies / explodeCorpse, ศัตรูที่ตายไปแล้วในสวิงเดียวกันข้าม
     + CombatClient: getSkillLook (ใหญ่ขึ้น / ฟันซ้ายขวา / สีธาตุ) ใช้กับสกิลคนอื่นด้วย, CorpseExplosion
     + InventoryClient: แถบ SKILL RUNES ล่างหน้าต่าง (หน้าต่างสูงขึ้น 70), รายละเอียดรูน,
       ปุ่ม Auto-Socket / Remove from Skill, Shift+คลิก = ใส่/ถอดรูน
     + ARCHITECTURE.md ทุกหัวข้อที่เกี่ยว + หัวข้อ RuneData + แถวบาลานซ์ + KNOWN ISSUES แถบสกิลยังไม่โชว์รูน
     + Google Doc "Project poe" + Project poe.docx: งานเฟส 7 + ไอเดียรูน = กำลังทำ, ถัดไป = หินคราฟต์
   - คีย์ลัดในกระเป๋า (InventoryClient) [ยังไม่ได้เทสใน Studio]:
     + Shift + คลิกของในกระเป๋า = สวมใส่ทันที, Shift + คลิกช่องสวมใส่ = ถอดทันที
     + ชี้ของในกระเป๋าแล้วกด X = ทิ้งทันทีไม่ถามยืนยัน (ของที่สวมอยู่ทิ้งด้วย X ไม่ได้)
     + ป้ายบอกคีย์ลัดที่หัวหน้าต่าง (PC เท่านั้น)
     + default.project.json: StarterPlayer.EnableMouseLockOption = false (ปิด Shift Lock ที่ทำเมาส์ค้างกลางจอ)
     + ARCHITECTURE.md: คีย์ลัดใน InventoryClient + หัวข้อค่าใน default.project.json
     + Google Doc "Project poe" + Project poe.docx: งานที่กำลังทำ + คีย์ลัดกระเป๋า
   - เฟส 7 ข้อ 2: ธาตุ + สถานะผิดปกติ + ค่าต้านทาน [ยังไม่ได้เทสใน Studio]:
     + Elements (ใหม่, ใช้ร่วม): ธาตุ Fire/Cold/Lightning, สี, ตัวเลข Ignite/Chill/Freeze/Shock,
       MAX_RESISTANCE 75%, formatAilments (ป้ายสีบน UI)
     + Ailments (ใหม่, server): ติดไฟ (เผา 100% ของดาเมจไฟใน 2 วิ), ช้า 30% 2 วิ,
       แข็ง 1 วิ (น้ำแข็งครั้งเดียว >= 10% เลือดสูงสุด, ยกเลิกท่าที่ศัตรูง้าง), ช็อต +5-30% ดาเมจ 3 วิ
       ใช้ได้ทั้งศัตรู/TrainingDummy/ผู้เล่น, ตั้ง attribute Ignited/Chilled/Frozen/Shocked บน Model
     + ItemData: affix FireDamage/ColdDamage/LightningDamage (Prefix +3-12),
       FireResistance/ColdResistance/LightningResistance (Suffix +8-25%)
     + PlayerStats/PlayerData: สเตตัสธาตุ 6 ตัว + attribute
     + CombatServer: ดาเมจ = กายภาพ + ธาตุ (คริคูณทั้งหมด) x ช็อต, แยก damageEnemy ใช้ทั้งตีและไฟเผา,
       แข็ง = ใช้สกิล/กลิ้งไม่ได้
     + EnemyData: Attack.Element (Grunt Physical, บอส Fire), EnemyService: หักค่าต้านทาน + ติดสถานะให้ผู้เล่น,
       ศัตรูแข็ง = AI หยุด + ยกเลิกท่าที่ง้าง
     + CombatClient: เลขดาเมจสีตามธาตุ (ไฟเผา = ส้ม), แข็ง = ตี/กลิ้งไม่ได้
     + HudClient: ป้าย BURN/CHILL/FROZEN/SHOCK เหนือแถบเลือดศัตรู, ต่อท้ายชื่อบอส, ของเราเหนือแถบเลือด
     + InventoryClient: สเตตัส ELE DMG + RES (สีตามธาตุ), ตัวหนังสือ 11 ให้พอ 5 บรรทัด
     + ARCHITECTURE.md ทุกหัวข้อที่เกี่ยว + KNOWN ISSUES 2 ข้อ (ยังไม่มีศัตรูน้ำแข็ง/สายฟ้า, วงแดงบอสตอนแข็ง)
     + Google Doc "Project poe" + Project poe.docx: งานเฟส 7 + ไอเดียข้อธาตุ = กำลังทำ, ถัดไป = รูนสลักหิน
   - เฟส 7 ต่อ: ขวดมานา + แถบมานา + Energy Shield + affix ES [ยังไม่ได้เทสใน Studio]:
     + มานา: สูงสุด 50 +4/เลเวล, ฟื้น 4%/วิ, SkillData.ManaCost (Slash ฟรี, Spin Slash 15)
       Client เช็คก่อนตี + ช่องสกิลทับสีน้ำเงินตอนมานาไม่พอ, CombatServer หักจริงหลังเช็คคูลดาวน์
     + Energy Shield: ได้จากไอเทมเท่านั้น, รับดาเมจศัตรูก่อนเลือด, ไม่โดนตี 3 วิ -> ชาร์จ 25%/วิ
       affix ใหม่ใน ItemData: EnergyShield (Prefix +10-35), EnergyShieldRecharge (Suffix +10-40%)
     + ขวดมานา: กด 2 / ปุ่ม Mana บนมือถือ (ฟื้น 50% ของมานาใน 1.5 วิ) ใช้ระบบเดียวกับขวดเลือด
       PlayerStats.FLASKS (Life/Mana) แทน FLASK_MAX_CHARGES / FLASK_HEAL_PERCENT / FLASK_DURATION,
       attribute LifeFlaskCharges / ManaFlaskCharges แทน FlaskCharges, FlaskRemote ส่ง kind
     + โมดูลใหม่ PlayerResources (+ PlayerResourcesServer): ถือมานา/ES/ขวดยา ทั้งหมด,
       ย้ายโค้ดขวดยาออกจาก PlayerData และ CombatServer มาไว้ที่นี่ (ฟื้นทีละ 0.1 วิ ในลูปเดียว)
     + EnemyService: ดาเมจลงผู้เล่นผ่าน PlayerResources.takeDamage, ประตู -> restoreAll
     + HudClient: แถบ ES (โชว์เมื่อมี ES) + มานา, InventoryClient: สเตตัส MP / ES / ES RECHARGE
     + Ui.Colors: Mana, EnergyShield
     + ARCHITECTURE.md: ทุกหัวข้อที่เกี่ยว + หัวข้อ PlayerResources + แถวบาลานซ์มานา/ES,
       README.md: เพิ่ม PlayerResources ในรายการสคริปต์ที่ห้ามแก้ใน Studio
     + Google Doc "Project poe" + Project poe.docx: งานเฟส 7 = ขวดยาเลือด/มานา + มานา + ES (รอเทส)
   - เริ่มเฟส 7: ขวดยาเลือด (ไอเดียข้อแรกในหัวข้อ 7 ของ Google Doc) [ยังไม่ได้เทสใน Studio]:
     + กด 1 / ปุ่ม Flask ข้างปุ่ม Dodge บนมือถือ -> ฮีล 40% ของเลือดสูงสุดใน 1.5 วิ, มี 3 ครั้ง,
       เลือดเต็มดื่มไม่ได้, ดื่มซ้ำไม่ได้จนกว่าจะฮีลจบ, ดื่มระหว่างกลิ้งได้
     + ได้คืนตอนฆ่า: +0.25 ครั้ง/ตัว (บอส +1) ให้ทุกคนที่ตีโดน, เต็มตอนเกิด + ผ่านประตูวาร์ป/ปุ่มกลับ Lobby
     + FlaskRemote ใหม่, PlayerStats (FLASK_*), PlayerData (refillFlask / addFlaskCharges /
       useFlaskCharge, attribute FlaskCharges ไม่เซฟ), CombatServer (เช็ค + ฮีลทีละนิด),
       EnemyService (ตาย -> ขวดยา, ประตู -> เติมเต็ม), CombatClient (ช่อง Flask มีน้ำแดงตามจำนวน +
       ประกายแดงตอนดื่ม, หมายเลขหัวข้อแถบสกิลเลื่อนเป็นข้อ 8)
     + ARCHITECTURE.md: เอกสารขวดยาทุกหัวข้อ + แถวบาลานซ์ขวดยา, แยกบรรทัด KNOWN ISSUES ที่ติดกัน
     + Google Doc "Project poe" + Project poe.docx: เฟส 7+ = กำลังทำ (เริ่ม 30/10, ขวดยาเลือด รอเทส),
       งานที่กำลังทำ = ขวดยาเลือด, ก้าวถัดไป = เทสแล้วไปข้อธาตุ + สถานะผิดปกติ
   - Google Doc "Project poe" + Project poe.docx: ใส่ไอเดียขยายเกมลงหัวข้อ "7. ไว้ทีหลัง" (เรียงจากคุ้มสุด):
     ขวดยาเลือด, ธาตุ + สถานะผิดปกติ, รูนสลักหิน (แต่งสกิล), หินคราฟต์, แผ่นศิลา (endgame),
     ผังพาสซีฟ + คลาส (ท้ายสุด) + ข้อควรระวังเรื่องไม่ใช้ชื่อ/ภาพ/ตัวเลขของ PoE,
     "ก้าวถัดไป" ในหัวข้อ 1 = หยิบไอเดียจากหัวข้อ 7 มาทำทีละอย่าง
   - เฟส 6 (ให้คนลองเล่น) ผ่าน = เฟส 1-6 เสร็จครบ ได้ MVP ตามขอบเขต:
     + Google Doc "Project poe" + Project poe.docx: เฟส 6 = เสร็จ (จบ 30/10), ติ๊กงานเฟส 6 ครบ,
       สถานะตอนนี้ = เฟส 7+ ขยายเกม (ยังไม่เริ่ม), งานต่อไป = เลือกฟีเจอร์แรกจาก "7. ไว้ทีหลัง"
   - เทสซ้ำผ่าน (มอนไม่วาปแล้ว, "!" ขึ้น, กลิ้งหลบผ่านวงบอสได้) + เฟส 1-5 เทสผ่านครบ:
     + KNOWN ISSUES: เอาเรื่องมอนวาปและ "ยังไม่ได้ playtest บาลานซ์" ออก
       (ตารางตัวเลขบาลานซ์ยังอยู่ใน ARCHITECTURE.md หัวข้อ 5 ไว้อ้างอิงตอนปรับค่า)
     + Google Doc "Project poe" + Project poe.docx: เฟส 1-5 = เสร็จ (จบ 30/10),
       ติ๊กทดสอบมือถือจำลอง / เข้าออกหลายรอบ / ปรับบาลานซ์, งานต่อไป = หาคนลองเล่น 3-5 คน
   - แก้จากเทสเฟส 6:
     + ศัตรูวาปมาตีตอนเจอครั้งแรก (EnemyService): ต้องมองเห็นผู้เล่นจริงถึงจะไล่ (Raycast จากระดับตา,
       ไม่ทะลุกำแพง), เห็นครั้งแรก = ยืนนิ่ง 0.6 วิ + "!" บนหัว (EnemyAlert -> CombatClient),
       ประตูเข้าด่านโหลดพื้นที่หน้าประตูบน Client ก่อนวาร์ป (RequestStreamAroundAsync)
     + เอากระโดดออก เปลี่ยนเป็นกลิ้งหลบ: Space / ปุ่ม Dodge บนมือถือ (ตรงที่เคยเป็นปุ่มกระโดด),
       CombatClient เคลื่อนตัว + ท่าตีลังกา, DodgeRemote ใหม่, CombatServer เช็คคูลดาวน์แล้วตั้ง
       InvulnerableUntil -> EnemyService ไม่ทำดาเมจช่วงนั้น, ค่าอยู่ใน PlayerStats (DODGE_*)
     + CombatClient: แยกการสร้างช่องในแถบสกิลเป็น createSlot (ใช้ทั้งสกิลและ Dodge)
     + Google Doc "Project poe" + Project poe.docx: เฟส 6 = กำลังทำ (เริ่ม 30/10) + ปัญหาที่เจอรอบแรก
   - อัปเดตเอกสารทั้งหมดให้ตรงโค้ดล่าสุด รวมงานของ WEE (41e769a..043131d): ด่าน + ประตูวาร์ป,
     MinimapClient + หน้าตั้งค่า, TeleportRemote, ช่องสวมใส่ 9 ช่อง + AllowOffHand, กระเป๋ากด B,
     ข้อความในเกมเป็นภาษาอังกฤษ (ชื่อสกิล/ศัตรู/ไอเทม/ข้อความแจ้งเตือนที่อ้างในเอกสาร + ปุ่ม ⚙️ -> SET)
     + โน้ตนี้: โครงสร้าง, QUICK EDIT GUIDE, รายการไฟล์ข้อ 3, สิ่งที่โค้ดต้องการจากแมพ (ประตูวาร์ป)
     + KNOWN ISSUES: เอา Workspace.Script1 ออก (WEE เอาออกจาก ARCHITECTURE.md แล้ว),
       เพิ่มประตูวาร์ปรีเซ็ตทั้งด่าน + Stone Grunt 10 ตัวรุม
     + ARCHITECTURE.md: RespawnTime ไม่ได้ใช้แล้ว, PlayerData (ย้ายช่องเก่า Weapon/Armor, กฎ OffHand,
       แหวน/Special), ของที่ประตูวาร์ปต้องมี (PortalPrompt) + ข้อความป้ายที่โค้ดตั้งทับ,
       ข้อจำกัดใหม่ในหัวข้อ 5, แก้คำผิด
     + README: เพิ่ม DungeonMap / MinimapClient ในตารางแยกงาน, ข้อความ error ในตารางปัญหาเป็นภาษาอังกฤษ
     + Project poe.docx: ให้ตรงกับ Google Doc "Project poe" (เอกสารแผน + ติดตามความคืบหน้า)
   [2026-10-29]
   - CombatServer / PlayerData: พารามิเตอร์จาก Remote ใช้ type any แทน unknown
     (ส่วนเสริม Roblox LSP รุ่นเก่าไม่รู้จัก unknown -> ขึ้นเตือนใน Problems, ผลการทำงานเหมือนเดิม)
   - แก้ KNOWN ISSUES:
     + ศัตรูมีท่าเดิน: แขนขาเป็น Motor6D (EnemyService) + EnemyVisualsClient แกว่งตามความเร็วเดิน
     + ศัตรูเดินอ้อมสิ่งกีดขวาง: ทางโล่ง = เดินตรง, ถ้ามีของขวาง (Blockcast ขนาดตัว) -> PathfindingService
     + เลือดศัตรู +50% ต่อผู้เล่นที่เพิ่มมา 1 คน (ปรับทันทีตอนคนเข้า/ออก คง % เลือดเดิม)
     + Highlight เกิน 31: EnemyVisualsClient เปิดเฉพาะ 27 อันที่ใกล้ตัวเราสุด (เหลือที่ให้คลื่นดาบ)
     + DataStore ใน Studio ที่ไม่มีสิทธิ์: ไม่ลองซ้ำ 3 รอบแล้ว, ขึ้น "เทสใน Studio: ... ไม่บันทึก"
       แทน "โหลดข้อมูลไม่สำเร็จ", DataStatus = "NoAccess"
     + บาลานซ์: คำนวณเวลาฆ่าแล้วอยู่ในช่วงที่โอเค (ดูข้อ 5) ยังไม่เปลี่ยนตัวเลข รอ playtest
   - MVP เวอร์ชันแรก (ตามเอกสารแผน Project poe หัวข้อ 3):
     + สกิลที่ 2 หมุนฟัน (SpinSlash: คลิกขวา / Q, วงรอบตัว) + แถบสกิลแสดงคูลดาวน์
       + มือถือ: ปุ่มสกิลแตะได้, เล็งศัตรูใกล้สุดเอง / กดค้างตีต่อเนื่องได้ทุกสกิล
         (รวมการกดค้างของ WEE commit 067d4fc เข้าโค้ดใหม่, Cooldown ฟัน 0.15 -> 0.55)
     + ศัตรู 2 ชนิด (EnemyData + EnemyService): ภูตหิน (ตีใกล้) + บอสยักษ์หิน (ทุบเป็นวง)
       AI ไล่/ตี/กลับบ้าน, เตือนก่อนโดนตี, ตาย -> EXP + ดรอป, เกิดใหม่, บอสตาย = เคลียร์ด่าน
     + ไอเทม (ItemData + Loot): ดาบเหล็ก / เสื้อเกราะหนัง, affix ดาเมจ / เลือด / ความเร็วโจมตี
       3 ระดับความหายาก, ดรอปบนพื้นกด E เก็บ
     + กระเป๋า (InventoryClient + PlayerData): 20 ช่อง, สวมใส่/ถอด/ทิ้ง, Server ตัดสินทั้งหมด
     + เลเวล/EXP (PlayerStats) + เซฟ DataStore (โหลดพลาด = ไม่เซฟทับ, autosave 2 นาที)
     + HUD: แถบเลือด/EXP, แถบเลือดศัตรู, แถบบอส, ข้อความ, หน้าจอตาย
     + CombatServer: คูลดาวน์แยกตามสกิล, หักความเร็วโจมตี, ดาเมจ + FlatDamage,
       ไม่ตีโดนผู้เล่นด้วยกัน (เดิมฟันโดนเพื่อนได้), ReplicateSlash -> ReplicateSkill
     + ARCHITECTURE.md เขียนใหม่ทั้งไฟล์ให้ตรงระบบใหม่
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
