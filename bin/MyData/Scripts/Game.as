// ==============================================
//
//    GameState Class for Game Manager
//
// ==============================================

class GameState : State
{
    void OnSceneLoadFinished(Scene@ _scene)
    {

    }

    void OnAsyncLoadProgress(Scene@ _scene, float progress, int loadedNodes, int totalNodes, int loadedResources, int totalResources)
    {

    }

    void OnKeyDown(int key)
    {
        if (key == KEY_ESC)
        {
             if (!console.visible)
                OnESC();
            else
                console.visible = false;
        }
    }

    void OnESC()
    {
        engine.Exit();
    }

    void OnSceneTimeScaleUpdated(Scene@ scene, float newScale)
    {
    }
};

enum LoadSubState
{
    LOADING_RESOURCES,
    LOADING_MOTIONS,
    LOADING_FINISHED,
};

class LoadingState : GameState
{
    int                 state = -1;
    int                 numLoadedResources = 0;
    Scene@              preloadScene;

    LoadingState()
    {
        SetName("LoadingState");
    }

    void CreateLoadingUI()
    {
        float alphaDuration = 1.0f;
        ValueAnimation@ alphaAnimation = ValueAnimation();
        alphaAnimation.SetKeyFrame(0.0f, Variant(0.0f));
        alphaAnimation.SetKeyFrame(alphaDuration, Variant(1.0f));
        alphaAnimation.SetKeyFrame(alphaDuration * 2, Variant(0.0f));

        Texture2D@ logoTexture = cache.GetResource("Texture2D", "Textures/ulogo.jpg");
        Sprite@ logoSprite = ui.root.CreateChild("Sprite", "logo");
        logoSprite.texture = logoTexture;
        int textureWidth = logoTexture.width;
        int textureHeight = logoTexture.height;
        logoSprite.SetScale(256.0f / textureWidth);
        logoSprite.SetSize(textureWidth, textureHeight);
        logoSprite.SetHotSpot(0, textureHeight);
        logoSprite.SetAlignment(HA_LEFT, VA_BOTTOM);
        logoSprite.SetPosition(graphics.width - textureWidth/2, 0);
        logoSprite.opacity = 0.75f;
        logoSprite.priority = -100;
        logoSprite.AddTag("TAG_LOADING");

        Text@ text = ui.root.CreateChild("Text", "loading_text");
        text.SetFont(cache.GetResource("Font", UI_FONT), UI_FONT_SIZE);
        text.SetAlignment(HA_LEFT, VA_BOTTOM);
        text.SetPosition(2, 0);
        text.color = Color(1, 1, 1);
        text.textEffect = TE_STROKE;
        text.AddTag("TAG_LOADING");

        Texture2D@ loadingTexture = cache.GetResource("Texture2D", "Textures/Loading.tga");
        Sprite@ loadingSprite = ui.root.CreateChild("Sprite", "loading_bg");
        loadingSprite.texture = loadingTexture;
        textureWidth = loadingTexture.width;
        textureHeight = loadingTexture.height;
        loadingSprite.SetSize(textureWidth, textureHeight);
        loadingSprite.SetPosition(graphics.width/2 - textureWidth/2, graphics.height/2 - textureHeight/2);
        loadingSprite.priority = -100;
        loadingSprite.opacity = 0.0f;
        loadingSprite.AddTag("TAG_LOADING");
        loadingSprite.SetAttributeAnimation("Opacity", alphaAnimation);
    }

    void Enter(State@ lastState)
    {
        State::Enter(lastState);
        if (!engine.headless)
            CreateLoadingUI();
        ChangeSubState(LOADING_RESOURCES);
    }

    void Exit(State@ nextState)
    {
        State::Exit(nextState);
        Array<UIElement@>@ elements = ui.root.GetChildrenWithTag("TAG_LOADING");
        for (uint i = 0; i < elements.length; ++i)
            elements[i].Remove();
    }

    void Update(float dt)
    {
        if (state == LOADING_RESOURCES)
        {

        }
        else if (state == LOADING_MOTIONS)
        {
            Text@ text = ui.root.GetChild("loading_text");
            if (text !is null)
                text.text = "Loading Motions, loaded = " + gMotionMgr.processedMotions;

            if (d_log)
                Print("============================== Motion Loading start ==============================");

            if (gMotionMgr.Update(dt))
            {
                gMotionMgr.Finish();
                ChangeSubState(LOADING_FINISHED);
                if (text !is null)
                    text.text = "Loading Scene Resources";
            }

            if (d_log)
                Print("============================== Motion Loading end ==============================");
        }
        else if (state == LOADING_FINISHED)
        {
            if (preloadScene !is null)
                preloadScene.Remove();
            preloadScene = null;
            gGame.ChangeState("TestGameState");
        }
    }

    void ChangeSubState(int newState)
    {
        if (state == newState)
            return;

        Print("LoadingState ChangeSubState from " + state + " to " + newState);
        state = newState;

        if (newState == LOADING_RESOURCES)
        {
            preloadScene = Scene();
            preloadScene.LoadAsyncXML(cache.GetFile("Scenes/animation.xml"), LOAD_RESOURCES_ONLY);
        }
        else if (newState == LOADING_MOTIONS)
            gMotionMgr.Start();
    }

    void OnSceneLoadFinished(Scene@ _scene)
    {
        if (state == LOADING_RESOURCES)
        {
            Print("Scene Loading Finished");
            ChangeSubState(LOADING_MOTIONS);
        }
    }

    void OnAsyncLoadProgress(Scene@ _scene, float progress, int loadedNodes, int totalNodes, int loadedResources, int totalResources)
    {
        Text@ text = ui.root.GetChild("loading_text");
        if (text !is null)
            text.text = "Loading scene ressources progress=" + progress + " resources:" + loadedResources + "/" + totalResources;
    }

    void OnESC()
    {
        if (state == LOADING_RESOURCES)
            preloadScene.StopAsyncLoading();
        engine.Exit();
    }
};

enum GameSubState
{
    GAME_FADING,
    GAME_RUNNING,
    GAME_FAIL,
    GAME_RESTARTING,
    GAME_PAUSE,
    GAME_WIN,
};

class TestGameState : GameState
{
    Scene@              gameScene;
    TextMenu@           pauseMenu;
    BorderImage@        fullscreenUI;

    int                 state = -1;
    int                 pauseState = -1;
    int                 maxKilled = 5;

    float               fadeTime;
    float               fadeInDuration = 2.0f;
    float               restartDuration = 5.0f;

    bool                postInited = false;

    TestGameState()
    {
        SetName("TestGameState");
        @pauseMenu = TextMenu(UI_FONT, UI_FONT_SIZE);
        fullscreenUI = BorderImage("FullScreenImage");
        fullscreenUI.visible = false;
        fullscreenUI.priority = -9999;
        fullscreenUI.opacity = 1.0f;
        fullscreenUI.texture = cache.GetResource("Texture2D", "Textures/fade.png");
        fullscreenUI.SetFullImageRect();
        if (!engine.headless)
            fullscreenUI.SetFixedSize(graphics.width, graphics.height);
        ui.root.AddChild(fullscreenUI);
        pauseMenu.texts.Push("RESUME");
        pauseMenu.texts.Push("EXIT");
    }

    ~TestGameState()
    {
        @pauseMenu = null;
        gameScene = null;
        fullscreenUI.Remove();
    }

    void Enter(State@ lastState)
    {
        state = -1;
        State::Enter(lastState);
        CreateScene();
        if (engine.headless)
            return;
        CreateViewPort();
        CreateUI();
        PostCreate();
        ChangeSubState(GAME_FADING);
    }

    void PostCreate()
    {
        Node@ zoneNode = gameScene.GetChild("zone", true);
        Zone@ zone = zoneNode.GetComponent("Zone");
        // zone.heightFog = false;
    }

    void CreateUI()
    {
        int height = graphics.height / 22;
        if (height > 64)
            height = 64;
        Text@ messageText = ui.root.CreateChild("Text", "message");
        messageText.SetFont(cache.GetResource("Font", UI_FONT), UI_FONT_SIZE);
        messageText.SetAlignment(HA_CENTER, VA_CENTER);
        messageText.SetPosition(0, -height * 2 + 100);
        messageText.color = Color(1, 0, 0);
        messageText.visible = false;

        Text@ statusText = ui.root.CreateChild("Text", "status");
        statusText.SetFont(cache.GetResource("Font", UI_FONT), UI_FONT_SIZE);
        statusText.SetAlignment(HA_LEFT, VA_BOTTOM);
        statusText.SetPosition(0, 0);
        statusText.color = Color(1, 1, 0);
        statusText.visible = true;

        Text@ inputText = ui.root.CreateChild("Text", "input");
        inputText.SetFont(cache.GetResource("Font", UI_FONT), UI_FONT_SIZE);
        inputText.SetAlignment(HA_LEFT, VA_BOTTOM);
        inputText.SetPosition(0, -UI_FONT_SIZE - 5);
        inputText.color = Color(0, 1, 1);
        inputText.visible = false;
    }

    void Exit(State@ nextState)
    {
        State::Exit(nextState);
    }

    void Update(float dt)
    {
        switch (state)
        {
        case GAME_FADING:
            {
                float t = fullscreenUI.GetAttributeAnimationTime("Opacity");
                if (t + 0.05f >= fadeTime)
                {
                    fullscreenUI.visible = false;
                    ChangeSubState(GAME_RUNNING);
                }
            }
            break;

        case GAME_FAIL:
        case GAME_WIN:
            {
                if (gInput.IsAttackPressed())
                {
                    ChangeSubState(GAME_RESTARTING);
                    ShowMessage("", false);
                }

            }
            break;

        case GAME_PAUSE:
            {
                int selection = pauseMenu.Update(dt);
                if (selection == 0)
                    ChangeSubState(pauseState);
                else if (selection == 1)
                    engine.Exit();
            }
            break;

        case GAME_RUNNING:
            {
                if (!postInited) {
                    if (timeInState > 2.0f) {
                        postInit();
                        postInited = true;
                    }
                }
            }
            break;
        }
        GameState::Update(dt);
    }

    void ChangeSubState(int newState)
    {
        if (state == newState)
            return;

        int oldState = state;
        Print("TestGameState ChangeSubState from " + oldState + " to " + newState);
        state = newState;
        timeInState = 0.0f;

        script.defaultScene.updateEnabled = !(newState == GAME_PAUSE);
        fullscreenUI.SetAttributeAnimationSpeed("Opacity", newState == GAME_PAUSE ? 0.0f : 1.0f);

        if (newState == GAME_PAUSE)
            pauseMenu.Add();
        else
            pauseMenu.Remove();

        Player@ player = GetPlayer();

        switch (newState)
        {
        case GAME_RUNNING:
            {
                if (player !is null)
                    player.RemoveFlag(FLAGS_INVINCIBLE);

                freezeInput = false;
            }
            break;

        case GAME_FADING:
            {
                if (oldState != GAME_PAUSE)
                {
                    ValueAnimation@ alphaAnimation = ValueAnimation();
                    alphaAnimation.SetKeyFrame(0.0f, Variant(1.0f));
                    alphaAnimation.SetKeyFrame(fadeInDuration, Variant(0.0f));
                    fadeTime = fadeInDuration;
                    fullscreenUI.visible = true;
                    fullscreenUI.SetAttributeAnimation("Opacity", alphaAnimation, WM_ONCE);
                }

                freezeInput = true;
                if (player !is null)
                    player.AddFlag(FLAGS_INVINCIBLE);
            }
            break;

        case GAME_RESTARTING:
            {
                if (oldState != GAME_PAUSE)
                {
                    ValueAnimation@ alphaAnimation = ValueAnimation();
                    alphaAnimation.SetKeyFrame(0.0f, Variant(0.0f));
                    alphaAnimation.SetKeyFrame(restartDuration/2, Variant(1.0f));
                    alphaAnimation.SetKeyFrame(restartDuration, Variant(0.0f));
                    fadeTime = restartDuration;
                    fullscreenUI.opacity = 0.0f;
                    fullscreenUI.visible = true;
                    fullscreenUI.SetAttributeAnimation("Opacity", alphaAnimation, WM_ONCE);
                }

                freezeInput = true;
                if (player !is null)
                {
                    player.Reset();
                    player.AddFlag(FLAGS_INVINCIBLE);
                }
            }
            break;

        case GAME_PAUSE:
            {
                // ....
            }
            break;

        case GAME_WIN:
            {
                ShowMessage("You Win! Press Stride to restart!", true);
            }
            break;

        case GAME_FAIL:
            {
                ShowMessage("You Died! Press Stride to restart!", true);
            }
            break;
        }
    }

    void CreateViewPort()
    {
        Viewport@ viewport = Viewport(script.defaultScene, gCameraMgr.GetCamera());
        renderer.viewports[0] = viewport;
        RenderPath@ renderpath = viewport.renderPath.Clone();
        if (render_features & RF_HDR != 0)
        {
            // if (reflection)
            //    renderpath.Load(cache.GetResource("XMLFile","RenderPaths/ForwardHWDepth.xml"));
            // else
            renderpath.Load(cache.GetResource("XMLFile","RenderPaths/ForwardDepth.xml"));
            renderpath.Append(cache.GetResource("XMLFile","PostProcess/AutoExposure.xml"));
            renderpath.Append(cache.GetResource("XMLFile","PostProcess/BloomHDR.xml"));
            renderpath.Append(cache.GetResource("XMLFile","PostProcess/Tonemap.xml"));
            renderpath.SetEnabled("TonemapReinhardEq3", false);
            renderpath.SetEnabled("TonemapUncharted2", true);
            renderpath.shaderParameters["TonemapMaxWhite"] = 1.8f;
            renderpath.shaderParameters["TonemapExposureBias"] = 2.5f;
            renderpath.shaderParameters["AutoExposureAdaptRate"] = 2.0f;
            renderpath.shaderParameters["BloomHDRMix"] = Variant(Vector2(0.9f, 0.6f));
        }
        renderpath.Append(cache.GetResource("XMLFile", "PostProcess/FXAA2.xml"));
        renderpath.Append(cache.GetResource("XMLFile","PostProcess/ColorCorrection.xml"));
        viewport.renderPath = renderpath;
        SetColorGrading(colorGradingIndex);
    }

    void CreateScene()
    {
        uint t = time.systemTime;
        Scene@ scene_ = Scene();
        script.defaultScene = scene_;
        String scnFile = "Scenes/2.xml";
        scene_.LoadXML(cache.GetFile(scnFile));
        Print("loading-scene XML --> time-cost " + (time.systemTime - t) + " ms");

        Node@ cameraNode = scene_.CreateChild(CAMERA_NAME);
        Camera@ cam = cameraNode.CreateComponent("Camera");
        cam.fov = BASE_FOV;
        cameraId = cameraNode.id;
        cameraNode.worldPosition = Vector3(0, 10, -5);

        Node@ tmpPlayerNode = scene_.GetChild("player", true);
        Vector3 playerPos;
        Quaternion playerRot;
        if (tmpPlayerNode !is null)
        {
            playerPos = tmpPlayerNode.worldPosition;
            playerRot = tmpPlayerNode.worldRotation;
            tmpPlayerNode.Remove();
        }

        Node@ playerNode = CreateCharacter("player", "BATMAN/batman/batman.xml", "Batman", playerPos, playerRot);
        audio.listener = playerNode.GetChild(HEAD, true).CreateComponent("SoundListener");
        playerId = playerNode.id;

        // preprocess current scene
        Array<uint> nodes_to_remove;
        int enemyNum = 0;
        for (uint i=0; i<scene_.numChildren; ++i)
        {
            Node@ _node = scene_.children[i];
            Print("_node.name=" + _node.name);
            if (_node.name.StartsWith("preload_"))
                nodes_to_remove.Push(_node.id);
            else if (_node.name.StartsWith("light"))
            {
                Light@ light = _node.GetComponent("Light");
                if (render_features & RF_SHADOWS == 0)
                    light.castShadows = false;
                light.shadowBias = BiasParameters(0.00025f, 0.5f);
                light.shadowCascade = CascadeParameters(10.0f, 50.0f, 200.0f, 0.0f, 0.8f);
            }
        }

        for (uint i=0; i<nodes_to_remove.length; ++i)
            scene_.GetNode(nodes_to_remove[i]).Remove();

        gCameraMgr.Start(cameraNode);
        //gCameraMgr.SetCameraController("Debug");
        gCameraMgr.SetCameraController("ThirdPerson");

        gameScene = scene_;

        Node@ lightNode = scene_.GetChild("light");
        if (lightNode !is null)
        {
            Follow@ f = cast<Follow>(lightNode.CreateScriptObject(scriptFile, "Follow"));
            f.toFollow = playerId;
            f.offset = Vector3(0, 10, 0);
        }

        //DumpSkeletonNames(playerNode);
        Print("CreateScene() --> total time-cost " + (time.systemTime - t) + " ms.");
    }

    void ShowMessage(const String&in msg, bool show)
    {
        Text@ messageText = ui.root.GetChild("message", true);
        if (messageText !is null)
        {
            messageText.text = msg;
            messageText.visible = true;
        }
    }

    void OnKeyDown(int key)
    {
        if (key == KEY_ESC)
        {
            engine.Exit();
            return;

            int oldState = state;
            if (oldState == GAME_PAUSE)
                ChangeSubState(pauseState);
            else
            {
                ChangeSubState(GAME_PAUSE);
                pauseState = oldState;
            }
            return;
        }

        GameState::OnKeyDown(key);
    }

    void OnSceneTimeScaleUpdated(Scene@ scene, float newScale)
    {
        if (gameScene !is scene)
            return;
        // ApplyBGMScale(newScale *  GetPlayer().timeScale);
    }

    void ApplyBGMScale(float scale)
    {
        if (musicNode is null)
            return;
        Print("Game::ApplyBGMScale " + scale);
        SoundSource@ s = musicNode.GetComponent("SoundSource");
        if (s is null)
            return;
        s.frequency = BGM_BASE_FREQ * scale;
    }

    String GetDebugText()
    {
        return  " name=" + name + " timeInState=" + timeInState + " state=" + state + " pauseState=" + pauseState + "\n";
    }

    void postInit()
    {
        if (bHdr && graphics !is null)
            renderer.viewports[0].renderPath.shaderParameters["AutoExposureAdaptRate"] = 0.6f;
    }
};

class GameFSM : FSM
{
    GameState@ gameState;

    GameFSM()
    {
        Print("GameFSM()");
    }

    ~GameFSM()
    {
        Print("~GameFSM()");
    }

    void Start()
    {
        AddState(LoadingState());
        AddState(TestGameState());
    }

    bool ChangeState(const StringHash&in nameHash)
    {
        bool b = FSM::ChangeState(nameHash);
        if (b)
            @gameState = cast<GameState>(currentState);
        return b;
    }

    void OnSceneLoadFinished(Scene@ _scene)
    {
        if (gameState !is null)
            gameState.OnSceneLoadFinished(_scene);
    }

    void OnAsyncLoadProgress(Scene@ _scene, float progress, int loadedNodes, int totalNodes, int loadedResources, int totalResources)
    {
        if (gameState !is null)
            gameState.OnAsyncLoadProgress(_scene, progress, loadedNodes, totalNodes, loadedResources, totalResources);
    }

    void OnKeyDown(int key)
    {
        if (gameState !is null)
            gameState.OnKeyDown(key);
    }

    void OnSceneTimeScaleUpdated(Scene@ scene, float newScale)
    {
        if (gameState !is null)
            gameState.OnSceneTimeScaleUpdated(scene, newScale);
    }
};


GameFSM@ gGame = GameFSM();