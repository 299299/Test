// ------------------------------------------------
#include "Scripts/Game.as"
#include "Scripts/AssetProcess.as"
#include "Scripts/Motion.as"
#include "Scripts/PhysicsDrag.as"
#include "Scripts/Input.as"
#include "Scripts/FSM.as"
#include "Scripts/Ragdoll.as"
#include "Scripts/Camera.as"
#include "Scripts/Menu.as"
#include "Scripts/HeadIndicator.as"
#include "Scripts/Follow.as"
#include "Scripts/PhysicsSensor.as"
// ------------------------------------------------
#include "Scripts/GameObject.as"
#include "Scripts/Character.as"
#include "Scripts/Enemy.as"
#include "Scripts/Thug.as"
#include "Scripts/Player.as"
#include "Scripts/Bruce.as"
#include "Scripts/PlayerCombat.as"
#include "Scripts/PlayerMovement.as"

enum RenderFeature
{
    RF_NONE     = 0,
    RF_SHADOWS  = (1 << 0),
    RF_HDR      = (1 << 1),

    RF_FULL     = RF_SHADOWS | RF_HDR,
};

int drawDebug = 0;
bool bHdr = false;
bool bigHeadMode = false;
bool nobgm = true;

Node@ musicNode;
float BGM_BASE_FREQ = 44100;

String CAMERA_NAME = "Camera";

uint cameraId = M_MAX_UNSIGNED;
uint playerId = M_MAX_UNSIGNED;

int test_enemy_num_override = 3;
int render_features = RF_NONE;

String LUT = "";
const String UI_FONT = "Fonts/GAEN.ttf";
int UI_FONT_SIZE = 40;

int freeze_ai = 0;
int test_beat_index = 1;
bool base_on_player = false;
int test_counter_index = 0;
int test_double_counter_index = 0;
int test_triple_counter_index = 0;
int collision_type = 0;

bool mobile = false;

GameInput@ gInput = GameInput();

void Start()
{
    LogPrint("Game Running Platform: " + GetPlatform());
    mobile = (GetPlatform() == "Android" || GetPlatform() == "iOS");

    Array<String>@ arguments = GetArguments();
    for (uint i = 0; i < arguments.length; ++i)
    {
        String argument = arguments[i].ToLower();
        if (argument[0] == '-')
        {
            argument = argument.Substring(1);
            if (argument == "bgm")
                nobgm = !nobgm;
            else if (argument == "bighead")
                bigHeadMode = !bigHeadMode;
            else if (argument == "lowend")
                render_features = RF_NONE;
            else if (argument == "freezeai")
                freeze_ai = 1;
            else if (argument == "reflection")
                reflection = !reflection;
        }
    }

    cache.autoReloadResources = !mobile;
    engine.pauseMinimized = true;
    script.defaultScriptFile = scriptFile;
    if (renderer !is null && (render_features & RF_HDR != 0))
        renderer.hdrRendering = true;

    SetRandomSeed(time.systemTime);
    @gMotionMgr = BM_Game_MotionManager();

    SetWindowTitleAndIcon();
    CreateConsoleAndDebugHud();
    CreateUI();
    InitAudio();

    SubscribeToEvents();

    gGame.Start();
    gGame.ChangeState("LoadingState");

    gInput.InitTouch();

    LogPrint("Start Finished !!! ");
}

void Stop()
{
    LogPrint("Test Stop");
    gMotionMgr.Stop();
    ui.Clear();
}

void InitAudio()
{
    audio.masterGain[SOUND_MASTER] = 0.5f;
    audio.masterGain[SOUND_MUSIC] = 0.5f;
    audio.masterGain[SOUND_EFFECT] = 1.0f;

    if (!nobgm)
    {
        Sound@ musicFile = cache.GetResource("Sound", "Sfx/bgm.ogg");
        musicFile.looped = true;

        BGM_BASE_FREQ = musicFile.frequency;

        // Note: the non-positional sound source component need to be attached to a node to become effective
        // Due to networked mode clearing the scene on connect, do not attach to the scene itself
        musicNode = Node();
        SoundSource@ musicSource = musicNode.CreateComponent("SoundSource");
        musicSource.soundType = SOUND_MUSIC;
        musicSource.gain = 0.5f;
        musicSource.Play(musicFile);
    }
}

void SetWindowTitleAndIcon()
{
    Image@ icon = cache.GetResource("Image", "Textures/UrhoIcon.png");
    graphics.windowIcon = icon;
}

void CreateConsoleAndDebugHud()
{
    // Get default style
    XMLFile@ xmlFile = cache.GetResource("XMLFile", "UI/DefaultStyle.xml");
    if (xmlFile is null)
        return;

    // Create consoleui
    Console@ console = engine.CreateConsole();
    console.defaultStyle = xmlFile;
    console.background.opacity = 0.8f;

    // Create debug HUD
    DebugHud@ debugHud = engine.CreateDebugHud();
    debugHud.defaultStyle = xmlFile;
}

void CreateUI()
{
    ui.root.defaultStyle = cache.GetResource("XMLFile", "UI/DefaultStyle.xml");
    // Create a Cursor UI element because we want to be able to hide and show it at will. When hidden, the mouse cursor will
    // control the camera, and when visible, it will point the raycast target
    XMLFile@ style = cache.GetResource("XMLFile", "UI/DefaultStyle.xml");
    Cursor@ cursor = Cursor();
    cursor.SetStyleAuto(style);
    ui.cursor = cursor;
    cursor.visible = false;

    // Set starting position of the cursor at the rendering window center
    //cursor.SetPosition(graphics.width / 2, graphics.height / 2);
    //input.SetMouseVisible(true);
    Text@ text = ui.root.CreateChild("Text", "debug");
    text.SetFont(cache.GetResource("Font", "Fonts/Anonymous Pro.ttf"), 12);
    text.horizontalAlignment = HA_LEFT;
    text.verticalAlignment = VA_TOP;
    text.SetPosition(5, 50);
    text.color = Color(0, 0, 1);
    text.priority = -99999;
    // text.textEffect = TE_SHADOW;
}

void ShootBox(Scene@ _scene)
{
    Node@ cameraNode = gCameraMgr.GetCameraNode();
    Node@ boxNode = _scene.CreateChild("SmallBox");
    boxNode.position = cameraNode.position;
    boxNode.rotation = cameraNode.rotation;
    boxNode.SetScale(1.0);
    StaticModel@ boxObject = boxNode.CreateComponent("StaticModel");
    boxObject.model = cache.GetResource("Model", "Models/Box.mdl");
    boxObject.material = cache.GetResource("Material", "Materials/StoneEnvMapSmall.xml");
    boxObject.castShadows = true;
    RigidBody@ body = boxNode.CreateComponent("RigidBody");
    body.mass = 0.25f;
    body.friction = 0.75f;
    body.collisionLayer = COLLISION_LAYER_PROP;
    CollisionShape@ shape = boxNode.CreateComponent("CollisionShape");
    shape.SetBox(Vector3(1.0f, 1.0f, 1.0f));
    body.linearVelocity = cameraNode.rotation * Vector3(0.0f, 0.25f, 1.0f) * 10.0f;
}

void ShootSphere(Scene@ _scene)
{
    Node@ cameraNode = gCameraMgr.GetCameraNode();
    Node@ sphereNode = _scene.CreateChild("Sphere");
    sphereNode.position = cameraNode.position;
    sphereNode.rotation = cameraNode.rotation;
    sphereNode.SetScale(1.0);
    StaticModel@ boxObject = sphereNode.CreateComponent("StaticModel");
    boxObject.model = cache.GetResource("Model", "Models/Sphere.mdl");
    boxObject.material = cache.GetResource("Material", "Materials/StoneSmall.xml");
    boxObject.castShadows = true;
    RigidBody@ body = sphereNode.CreateComponent("RigidBody");
    body.mass = 1.0f;
    body.rollingFriction = 0.15f;
    body.collisionLayer = COLLISION_LAYER_PROP;
    CollisionShape@ shape = sphereNode.CreateComponent("CollisionShape");
    shape.SetSphere(1.0f);
    body.linearVelocity = cameraNode.rotation * Vector3(0.0f, 0.25f, 1.0f) * 10.0f;
}


void CreateEnemy(Scene@ _scene)
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return;

    EnemyManager@ em = GetEnemyMgr();
    if (em is null)
        return;

    IntVector2 pos = ui.cursorPosition;
    // Check the cursor is visible and there is no UI element in front of the cursor
    if (ui.GetElementAt(pos, true) !is null)
            return;

    Camera@ camera = GetCamera();
    if (camera is null)
        return;

    Ray cameraRay = camera.GetScreenRay(float(pos.x) / graphics.width, float(pos.y) / graphics.height);
    float rayDistance = 100.0f;
    PhysicsRaycastResult result = scene_.physicsWorld.RaycastSingle(cameraRay, rayDistance, COLLISION_LAYER_LANDSCAPE);
    if (result.body is null)
        return;

    if (result.body.node.name != "floor")
        return;

    em.CreateEnemy(result.position, Quaternion(0, Random(360), 0), "Thug");
}

Player@ GetPlayer()
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return null;
    Node@ characterNode = scene_.GetNode(playerId);
    if (characterNode is null)
        return null;
    return cast<Player>(characterNode.scriptObject);
}

Camera@ GetCamera()
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return null;
    Node@ cameraNode = scene_.GetNode(cameraId);
    if (cameraNode is null)
        return null;
    return cameraNode.GetComponent("Camera");
}

EnemyManager@ GetEnemyMgr()
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return null;
    return cast<EnemyManager>(scene_.GetScriptObject("EnemyManager"));
}

void SubscribeToEvents()
{
    SubscribeToEvent("Update", "HandleUpdate");
    SubscribeToEvent("PostRenderUpdate", "HandlePostRenderUpdate");
    SubscribeToEvent("KeyDown", "HandleKeyDown");
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown");
    SubscribeToEvent("AsyncLoadFinished", "HandleSceneLoadFinished");
    SubscribeToEvent("AsyncLoadProgress", "HandleAsyncLoadProgress");
    SubscribeToEvent("CameraEvent", "HandleCameraEvent");
    SubscribeToEvent("SliderChanged", "HandleSliderChanged");
}

void HandleUpdate(StringHash eventType, VariantMap& eventData)
{
    float timeStep = eventData["TimeStep"].GetFloat();

    gInput.Update(timeStep);
    gCameraMgr.Update(timeStep);
    gGame.Update(timeStep);

    ExecuteCommand();

    if (script.defaultScene is null)
        return;

    if (drawDebug > 0)
    {
        String seperator = "-------------------------------------------------------------------------------------------------------\n";
        String debugText = seperator;
        debugText += gGame.GetDebugText();
        debugText += seperator;
        debugText += "current LUT: " + LUT + "\n";
        debugText += gCameraMgr.GetDebugText();
        debugText += gInput.GetDebugText();
        debugText += seperator;
        Player@ player = GetPlayer();
        if (player !is null)
            debugText += player.GetDebugText();
        debugText += seperator;
        if (drawDebug > 1)
        {
            EnemyManager@ em = GetEnemyMgr();
            if (em !is null && !em.enemyList.empty)
            {
                debugText += em.enemyList[0].GetDebugText();
                debugText += seperator;
            }
        }

        Text@ text = ui.root.GetChild("debug", true);
        if (text !is null)
            text.text = debugText;
    }
}

void HandlePostRenderUpdate(StringHash eventType, VariantMap& eventData)
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return;

    DebugRenderer@ debug = scene_.debugRenderer;
    if (drawDebug == 0)
        return;

    if (drawDebug > 0)
    {
        // gCameraMgr.DebugDraw(debug);
        debug.AddNode(scene_, 1.0f, false);
        Player@ player = GetPlayer();
        if (player !is null)
            player.DebugDraw(debug);
    }
    if (drawDebug > 1)
    {
        EnemyManager@ em = GetEnemyMgr();
        if (em !is null)
            em.DebugDraw(debug);
    }
    if (drawDebug > 2)
        scene_.physicsWorld.DrawDebugGeometry(true);
}

void HandleKeyDown(StringHash eventType, VariantMap& eventData)
{
    Scene@ scene_ = script.defaultScene;
    int key = eventData["Key"].GetInt();
    gGame.OnKeyDown(key);

    if (key == KEY_F1)
    {
        ++drawDebug;
        if (drawDebug > 3)
            drawDebug = 0;

        Text@ text = ui.root.GetChild("debug", true);
        if (text !is null)
            text.visible = drawDebug != 0;
    }
    else if (key == KEY_F2)
        debugHud.ToggleAll();
    else if (key == KEY_F3)
        console.Toggle();
    else if (key == KEY_F4)
    {
        Camera@ cam = GetCamera();
        if (cam !is null)
            cam.fillMode = (cam.fillMode == FILL_SOLID) ? FILL_WIREFRAME : FILL_SOLID;
    }
    else if (key == KEY_F5)
        ToggleDebugWindow();
    else if (key == KEY_1)
        ShootSphere(scene_);
    else if (key == KEY_2)
        ShootBox(scene_);
    else if (key == KEY_3)
        CreateEnemy(scene_);
    else if (key == KEY_4)
    {
        CameraController@ cc = gCameraMgr.currentController;
        if (cc.nameHash == StringHash("Debug"))
        {
            ui.cursor.visible = false;
            gCameraMgr.SetCameraController("ThirdPerson");
        }
        else
        {
            ui.cursor.visible = true;
            gCameraMgr.SetCameraController("Debug");
        }
    }
    else if (key == KEY_5)
    {
        VariantMap data;
        data[TARGET_FOV] = 60;
        SendEvent("CameraEvent", data);
    }
    else if (key == 'R')
        scene_.updateEnabled = !scene_.updateEnabled;
    else if (key == 'T')
    {
        if (scene_.timeScale >= 0.999f)
            scene_.timeScale = 0.1f;
        else
            scene_.timeScale = 1.0f;
    }
    else if (key == 'Q')
        engine.Exit();
    else if (key == 'J')
        TestAnimations_Group_2();
    else if (key == 'K')
        TestAnimations_Group_3();
    else if (key == 'L')
        TestAnimations_Group_4();
    else if (key == 'H')
        TestAnimations_Group_Beat();
    else if (key == 'E')
    {
        Array<String> testAnimations;
        //String testName = "TG_Getup/GetUp_Back";
        //String testName = "TG_BM_Counter/Counter_Leg_Front_01";
        //String testName = "TG_HitReaction/Push_Reaction";
        //String testName = "BM_TG_Beatdown/Beatdown_Strike_End_01";
        //String testName = "TG_HitReaction/HitReaction_Back_NoTurn";
        //String testName = "BM_Attack/Attack_Far_Back_04";
        //String testName = "TG_BM_Counter/Double_Counter_2ThugsB_01";
        //String testName = "BM_Attack/Attack_Far_Back_03";
        //String testName = "BM_Climb/Stand_Climb_Up_256_Hang";
        //String testName = GetAnimationName("BM_Railing/Railing_Idle");
        //String testName = ("BM_Railing/Railing_Climb_Down_Forward");
        //String testName = "BM_Climb/Stand_Climb_Up_256_Hang";
        String testName = "BM_Climb/Dangle_To_Hang"; //"BM_Climb/Walk_Climb_Down_128"; //"BM_Climb/Stand_Climb_Up_256_Hang";
        Player@ player = GetPlayer();
        testAnimations.Push(testName);
        //testAnimations.Push("BM_Climb/Dangle_Right");
        // testAnimations.Push(GetAnimationName("BM_Railing/Railing_Run_Forward_Idle"));
        if (player !is null)
            player.TestAnimation(testAnimations);
    }
    else if (key == 'F')
    {
        scene_.timeScale = 1.0f;
        // SetWorldTimeScale(scene_, 1);
    }
    else if (key == 'O')
    {
        Node@ n = scene_.GetChild("thug2");
        if (n !is null)
        {
            n.vars[ANIMATION_INDEX] = RandomInt(4);
            Thug@ thug = cast<Thug>(n.scriptObject);
            thug.ChangeState("HitState");
        }
    }
    else if (key == 'I')
    {
        Player@ p = GetPlayer();
        if (p !is null)
            p.SetPhysicsType(1 - p.physicsType);
    }
    else if (key == 'M')
    {
        Player@ p = GetPlayer();
        if (p !is null)
        {
            LogPrint("------------------------------------------------------------");
            for (uint i=0; i<p.stateMachine.states.length; ++i)
            {
                State@ s = p.stateMachine.states[i];
                LogPrint("name=" + s.name + " nameHash=" + s.nameHash.ToString());
            }
            LogPrint("------------------------------------------------------------");
        }
    }
    else if (key == 'U')
    {
        Player@ p = GetPlayer();
        if (p.timeScale > 1.0f)
            p.timeScale = 1.0f;
        else
            p.timeScale = 1.25f;
    }
}

void HandleMouseButtonDown(StringHash eventType, VariantMap& eventData)
{
    int button = eventData["Button"].GetInt();
    if (button == MOUSEB_RIGHT)
    {
        IntVector2 pos = ui.cursorPosition;
        // Check the cursor is visible and there is no UI element in front of the cursor
        if (ui.GetElementAt(pos, true) !is null)
            return;

        CreateDrag(float(pos.x), float(pos.y));
        SubscribeToEvent("MouseMove", "HandleMouseMove");
        SubscribeToEvent("MouseButtonUp", "HandleMouseButtonUp");
    }
}

void HandleMouseButtonUp(StringHash eventType, VariantMap& eventData)
{
    int button = eventData["Button"].GetInt();
    if (button == MOUSEB_RIGHT)
    {
        DestroyDrag();
        UnsubscribeFromEvent("MouseMove");
        UnsubscribeFromEvent("MouseButtonUp");
    }
}

void HandleMouseMove(StringHash eventType, VariantMap& eventData)
{
    int x = input.mousePosition.x;
    int y = input.mousePosition.y;
    MoveDrag(float(x), float(y));
}

void HandleSceneLoadFinished(StringHash eventType, VariantMap& eventData)
{
    LogPrint("HandleSceneLoadFinished");
    gGame.OnSceneLoadFinished(eventData["Scene"].GetPtr());
}

void HandleAsyncLoadProgress(StringHash eventType, VariantMap& eventData)
{
    LogPrint("HandleAsyncLoadProgress");
    Scene@ _scene = eventData["Scene"].GetPtr();
    float progress = eventData["Progress"].GetFloat();
    int loadedNodes = eventData["LoadedNodes"].GetInt();
    int totalNodes = eventData["TotalNodes"].GetInt();
    int loadedResources = eventData["LoadedResources"].GetInt();
    int totalResources = eventData["TotalResources"].GetInt();
    gGame.OnAsyncLoadProgress(_scene, progress, loadedNodes, totalNodes, loadedResources, totalResources);
}

void HandleCameraEvent(StringHash eventType, VariantMap& eventData)
{
    gCameraMgr.OnCameraEvent(eventData);
}

void TestAnimation_Group(const String&in playerAnim, Array<String>@ thugAnims)
{
    Player@ player = GetPlayer();
    EnemyManager@ em = GetEnemyMgr();

    if (em.enemyList.length < thugAnims.length)
        return;

    Motion@ m_player = gMotionMgr.FindMotion(playerAnim);
    if (m_player is null)
        return;

    LogPrint("TestAnimation_Group " + playerAnim);

    Array<String> testAnims;

    for (uint i=0; i<thugAnims.length; ++i)
    {
        Motion@ m = gMotionMgr.FindMotion(thugAnims[i]);
        Enemy@ e = em.enemyList[i];
        Vector4 t = GetTargetTransform(player.GetNode(), m, m_player);
        e.Transform(Vector3(t.x, e.GetNode().worldPosition.y, t.z), Quaternion(0, t.w, 0));
        e.TestAnimation(thugAnims[i]);
    }
    player.TestAnimation(playerAnim);
    player.SetSceneTimeScale(0.0f);
}

void TestAnimation_Group_s(const String&in playerAnim, const String& thugAnim, bool baseOnPlayer = false)
{
    Player@ player = GetPlayer();
    EnemyManager@ em = GetEnemyMgr();

    if (em.enemyList.empty)
        return;

    Motion@ m_player = gMotionMgr.FindMotion(playerAnim);
    Motion@ m = gMotionMgr.FindMotion(thugAnim);
    Enemy@ e = em.enemyList[0];

    if (baseOnPlayer)
    {
        Vector4 t = GetTargetTransform(player.GetNode(), m, m_player);
        e.Transform(Vector3(t.x, e.GetNode().worldPosition.y, t.z), Quaternion(0, t.w, 0));
    }
    else
    {
        Vector4 t = GetTargetTransform(e.GetNode(), m_player, m);
        player.Transform(Vector3(t.x, player.GetNode().worldPosition.y, t.z), Quaternion(0, t.w, 0));
    }

    e.TestAnimation(thugAnim);
    player.TestAnimation(playerAnim);
}

void TestAnimations_Group_Beat()
{
    String playerAnim = "BM_Attack/Beatdown_Test_0" + test_beat_index;
    String thugAnim = "TG_BM_Beatdown/Beatdown_HitReaction_0" + test_beat_index;
    test_beat_index ++;
    if (test_beat_index > 6)
    {
        test_beat_index = 1;
        base_on_player = !base_on_player;
    }
    TestAnimation_Group_s(playerAnim, thugAnim, base_on_player);
}

void TestAnimations_Group_2()
{
    Player@ player = GetPlayer();
    EnemyManager@ em = GetEnemyMgr();
    if (em.enemyList.empty)
        return;

    Enemy@ e = em.enemyList[0];
    CharacterCounterState@ s1 = cast<CharacterCounterState>(player.FindState("CounterState"));
    CharacterCounterState@ s2 = cast<CharacterCounterState>(e.FindState("CounterState"));
    Motion@ m1, m2;
    int i = RandomInt(4);
    if (i == 0)
    {
        int k = RandomInt(s1.frontArmMotions.length);
        @m1 = s1.frontArmMotions[k];
        @m2 = s2.frontArmMotions[k];
    }
    else if (i == 1)
    {
        int k = RandomInt(s1.frontLegMotions.length);
        @m1 = s1.frontLegMotions[k];
        @m2 = s2.frontLegMotions[k];
    }
    else if (i == 2)
    {
        int k = RandomInt(s1.backArmMotions.length);
        @m1 = s1.backArmMotions[k];
        @m2 = s2.backArmMotions[k];
    }
    else if (i == 3)
    {
        int k = RandomInt(s1.backLegMotions.length);
        @m1 = s1.backLegMotions[k];
        @m2 = s2.backLegMotions[k];
    }

    Vector4 t = GetTargetTransform(e.GetNode(), m1, m2);
    player.Transform(Vector3(t.x, player.GetNode().worldPosition.y, t.z), Quaternion(0, t.w, 0));

    e.TestAnimation(m2.name);
    player.TestAnimation(m1.name);
    player.SetSceneTimeScale(0.0f);

    LogPrint("TestAnimations_Group_2 -> " + m1.name);
}

void TestAnimations_Group_3()
{
    Array<String> tests =
    {
        "Double_Counter_2ThugsA",
        "Double_Counter_2ThugsB",
        "Double_Counter_2ThugsC",
        "Double_Counter_2ThugsD",
        "Double_Counter_2ThugsE",
        "Double_Counter_2ThugsF",
        "Double_Counter_2ThugsG",
        "Double_Counter_2ThugsH"
    };
    String preFix = "BM";
    String test = tests[test_double_counter_index];
    test_double_counter_index ++;
    if (test_double_counter_index >= int(tests.length))
        test_double_counter_index = 0;
    String playerAnim = preFix + "_TG_Counter/" + test;
    Array<String> thugAnims;
    String thugAnim = "TG_" + preFix + "_Counter/" + test;
    thugAnims.Push(thugAnim + "_01");
    thugAnims.Push(thugAnim + "_02");
    TestAnimation_Group(playerAnim, thugAnims);
}

void TestAnimations_Group_4()
{
    String preFix = "BM";
    Array<String> tests =
    {
        "Double_Counter_3ThugsA",
        "Double_Counter_3ThugsB",
        "Double_Counter_3ThugsC"
    };
    String test = tests[test_triple_counter_index];
    test_triple_counter_index ++;
    if (test_triple_counter_index >= int(tests.length))
        test_triple_counter_index = 0;
    String playerAnim = preFix + "_TG_Counter/" + test;
    Array<String> thugAnims;
    String thugAnim = "TG_" + preFix + "_Counter/" + test;
    thugAnims.Push(thugAnim + "_01");
    thugAnims.Push(thugAnim + "_02");
    thugAnims.Push(thugAnim + "_03");
    TestAnimation_Group(playerAnim, thugAnims);
}

void ToggleDebugWindow()
{
    Window@ win = ui.root.GetChild("DebugWindow", true);
    if (win !is null)
    {
        win.Remove();
        input.SetMouseVisible(false);
        freezeInput = false;
        return;
    }

    win = Window();
    win.name = "DebugWindow";
    win.movable = true;
    win.resizable = true;
    win.opacity = 0.8f;
    win.SetLayout(LM_VERTICAL, 2, IntRect(2,4,2,4));
    win.SetAlignment(HA_LEFT, VA_TOP);
    win.SetStyleAuto();
    ui.root.AddChild(win);

    Text@ windowTitle = Text();
    windowTitle.text = "Debug Parameters";
    windowTitle.SetStyleAuto();
    win.AddChild(windowTitle);

    IntVector2 scrSize(graphics.width, graphics.height);
    IntVector2 winSize(scrSize);
    winSize.x = int(float(winSize.x) * 0.3f);
    winSize.y = int(float(winSize.y) * 0.5f);
    win.size = winSize;
    win.SetPosition(5, (scrSize.y - winSize.y)/3);
    input.SetMouseVisible(true);
    freezeInput = true;

    RenderPath@ path = renderer.viewports[0].renderPath;
    UIElement@ parent = win;
    CreateDebugSlider(parent, "TonemapMaxWhite", 0, 0.0f, 5.0f, path.shaderParameters["TonemapMaxWhite"].GetFloat());
    CreateDebugSlider(parent, "TonemapExposureBias", 0, 0.0f, 5.0f, path.shaderParameters["TonemapExposureBias"].GetFloat());
    //CreateDebugSlider(parent, "BloomHDRBlurRadius", 0, 0.0f, 10.0f, path.shaderParameters["BloomHDRBlurRadius"].GetFloat());
    CreateDebugSlider(parent, "BloomHDRMix_x", 1, 0.0f, 1.0f, path.shaderParameters["BloomHDRMix"].GetVector2().x);
    CreateDebugSlider(parent, "BloomHDRMix_y", 2, 0.0f, 5.0f, path.shaderParameters["BloomHDRMix"].GetVector2().y);
}

void CreateDebugSlider(UIElement@ parent, const String&in label, int tag, float min, float max, float cur)
{
    UIElement@ textContainer = UIElement();
    parent.AddChild(textContainer);
    textContainer.layoutMode = LM_HORIZONTAL;
    textContainer.SetStyleAuto();

    Text@ text = Text();
    textContainer.AddChild(text);
    text.text = label + ": ";
    text.SetStyleAuto();

    Text@ valueText = Text();
    textContainer.AddChild(valueText);
    valueText.name = label + "_value";
    valueText.text = String(cur);
    valueText.SetStyleAuto();

    Slider@ slider = Slider();
    slider.name = label;
    slider.SetStyleAuto();
    slider.range = max - min;
    slider.value = cur - min;
    slider.SetMinSize(2, 16);
    slider.vars[RANGE] = Vector2(min, max);
    slider.vars[TAG] = tag;
    parent.AddChild(slider);
}

void HandleSliderChanged(StringHash eventType, VariantMap& eventData)
{
    UIElement@ ui = eventData["Element"].GetPtr();
    float value = eventData["Value"].GetFloat();
    if (!ui.vars.Contains(TAG))
        return;

    Vector2 range = ui.GetVar(RANGE).GetVector2();
    value += range.x;
    int tag = ui.GetVar(TAG).GetInt();
    Text@ valueText = ui.parent.GetChild(ui.name + "_value", true);
    if (valueText !is null)
        valueText.text = String(value);

    RenderPath@ path = renderer.viewports[0].renderPath;

    switch (tag)
    {
    case 0:
        path.shaderParameters[ui.name] = value;
        break;
    case 1:
        {
            Vector2 v = path.shaderParameters["BloomHDRMix"].GetVector2();
            v.x = value;
            path.shaderParameters["BloomHDRMix"] = Variant(v);
        }
        break;
    case 2:
        {
            Vector2 v = path.shaderParameters["BloomHDRMix"].GetVector2();
            v.y = value;
            path.shaderParameters["BloomHDRMix"] = Variant(v);
        }
        break;
    }
}

void ExecuteCommand()
{
    String commands = GetConsoleInput();
    if(commands.length == 0)
        return;

    LogPrint("######### Console Input: [" + commands + "] #############");
    Array<String> command_list = commands.Split(',');
    String command = command_list.empty ? commands : command_list[0];

    if (command == "dump")
    {
        String debugText = "camera position=" + gCameraMgr.GetCameraNode().worldPosition.ToString() + "\n";
        debugText += gInput.GetDebugText();

        Scene@ scene_ = script.defaultScene;
        if (scene_ !is null)
        {
            Array<Node@> nodes = scene_.GetChildrenWithScript("GameObject", true);
            for (uint i=0; i<nodes.length; ++i)
            {
                GameObject@ object = cast<GameObject@>(nodes[i].scriptObject);
                if (object !is null)
                    debugText += object.GetDebugText();
            }
        }
        LogPrint(debugText);
    }
    else if (command == "anim")
    {
        String testName = "BM_Attack/Attack_Close_Forward_02";
        Player@ player = GetPlayer();
        if (player !is null)
            player.TestAnimation(testName);
    }
    else if (command == "stop")
    {
        gMotionMgr.Stop();
        Scene@ scene_ = script.defaultScene;
        if (scene_ is null)
            return;
        scene_.Clear();
    }
    else if (command == "attack")
    {
        Player@ player = GetPlayer();
        if (player !is null)
            player.Attack();
    }
    else if (command == "evade")
    {
        Player@ player = GetPlayer();
        if (player !is null)
            player.Evade();
    }
    else if (command == "counter")
    {
        Player@ player = GetPlayer();
        if (player !is null)
            player.Counter();
    }
    else if (command == "avoid")
    {
        EnemyManager@ em = GetEnemyMgr();
        if (em is null)
            return;
        em.CreateEnemy(Vector3(0,0,0), Quaternion(0,0,0), "Thug");
        em.CreateEnemy(Vector3(0,0,0), Quaternion(0,0,0), "Thug");
    }
    else if (command == "distract")
    {
        Player@ player = GetPlayer();
        if (player !is null)
            player.Distract();
    }
    else if (command == "kill")
    {
        Node@ _node = script.defaultScene.GetChild(command_list[1]);
        if (_node !is null)
        {
            Character@ c = cast<Character>(_node.scriptObject);
            if (c !is null)
                c.ChangeState("DeadState");
        }
    }
}

void LogPrint(const String&in msg)
{
    log.Debug(msg);
}

class BM_Game_MotionManager : MotionManager
{
    void AddMotions()
    {
        CreateBruceMotions();
        CreateThugMotions();
    }

    void AddTriggers()
    {
        AddBruceAnimationTriggers();
        AddThugAnimationTriggers();
    }
};