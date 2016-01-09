// ==============================================
//
//    Player Pawn and Controller Class
//
// ==============================================

const String MOVEMENT_GROUP = "BM_Combat_Movement/"; //"BM_Combat_Movement/"
const float MAX_COUNTER_DIST = 5.0f;
const float PLAYER_COLLISION_DIST = COLLISION_RADIUS * 1.8f;
const float DIST_SCORE = 10.0f;
const float ANGLE_SCORE = 30.0f;
const float THREAT_SCORE = 30.0f;
const float LAST_ENEMY_ANGLE = 45.0f;
const int   LAST_ENEMY_SCORE = 5;
const int   MAX_WEAK_ATTACK_COMBO = 3;
const float MAX_DISTRACT_DIST = 4.0f;
const float MAX_DISTRACT_DIR = 90.0f;
const int   HIT_WAIT_FRAMES = 3;
const float LAST_KILL_SPEED = 0.35f;

class PlayerStandState : CharacterState
{
    Array<String>   animations;

    PlayerStandState(Character@ c)
    {
        super(c);
        SetName("StandState");
        animations.Push(GetAnimationName(MOVEMENT_GROUP + "Stand_Idle"));
        animations.Push(GetAnimationName(MOVEMENT_GROUP + "Stand_Idle_01"));
        animations.Push(GetAnimationName(MOVEMENT_GROUP + "Stand_Idle_02"));
        flags = FLAGS_ATTACK;
    }

    void Enter(State@ lastState)
    {
        ownner.SetTarget(null);
        ownner.PlayAnimation(animations[RandomInt(animations.length)], LAYER_MOVE, true, 0.2f);
        CharacterState::Enter(lastState);
    }

    void Update(float dt)
    {
        if (!gInput.IsLeftStickInDeadZone() && gInput.IsLeftStickStationary())
        {
            int index = ownner.RadialSelectAnimation(4);
            ownner.GetNode().vars[ANIMATION_INDEX] = index -1;

            Print("Stand->Move|Turn hold-frames=" + gInput.m_leftStickHoldFrames + " hold-time=" + gInput.m_leftStickHoldTime);

            if (index == 0)
                ownner.ChangeState("MoveState");
            else
                ownner.ChangeState("TurnState");
        }

        ownner.ActionCheck(true, true, true, true);
        CharacterState::Update(dt);
    }
};

class PlayerTurnState : MultiMotionState
{
    float turnSpeed;

    PlayerTurnState(Character@ c)
    {
        super(c);
        SetName("TurnState");
        AddMotion(MOVEMENT_GROUP + "Turn_Right_90");
        AddMotion(MOVEMENT_GROUP + "Turn_Right_180");
        AddMotion(MOVEMENT_GROUP + "Turn_Left_90");
        flags = FLAGS_ATTACK;
    }

    void Update(float dt)
    {
        ownner.motion_deltaRotation += turnSpeed * dt;
        ownner.ActionCheck(true, true, true, true);
        if (motions[selectIndex].Move(ownner, dt))
        {
            ownner.CommonStateFinishedOnGroud();
            return;
        }

        CharacterState::Update(dt);
    }

    void Enter(State@ lastState)
    {
        ownner.SetTarget(null);
        MultiMotionState::Enter(lastState);
        Motion@ motion = motions[selectIndex];
        Vector4 endKey = motion.GetKey(motion.endTime);
        float motionTargetAngle = ownner.motion_startRotation + endKey.w;
        float targetAngle = ownner.GetTargetAngle();
        float diff = AngleDiff(targetAngle - motionTargetAngle);
        turnSpeed = diff / motion.endTime;
        Print("motionTargetAngle=" + String(motionTargetAngle) + " targetAngle=" + String(targetAngle) + " diff=" + String(diff) + " turnSpeed=" + String(turnSpeed));
    }
};

class PlayerMoveState : SingleMotionState
{
    float turnSpeed = 5.0f;

    PlayerMoveState(Character@ c)
    {
        super(c);
        SetName("MoveState");
        SetMotion(MOVEMENT_GROUP + "Walk_Forward");
        flags = FLAGS_ATTACK | FLAGS_MOVING;
    }

    void Update(float dt)
    {
        float characterDifference = ownner.ComputeAngleDiff();
        Node@ _node = ownner.GetNode();
        _node.Yaw(characterDifference * turnSpeed * dt);
        motion.Move(ownner, dt);

        // if the difference is large, then turn 180 degrees
        if ( (Abs(characterDifference) > FULLTURN_THRESHOLD) && gInput.IsLeftStickStationary() )
        {
            _node.vars[ANIMATION_INDEX] = 1;
            ownner.ChangeState("TurnState");
        }

        if (gInput.IsLeftStickInDeadZone() && gInput.HasLeftStickBeenStationary(0.1f))
            ownner.ChangeState("StandState");

        ownner.ActionCheck(true, true, true, true);
        CharacterState::Update(dt);
    }

    void Enter(State@ lastState)
    {
        ownner.SetTarget(null);
        motion.Start(ownner, 0.0f, 0.1f, 1.25f);
        CharacterState::Enter(lastState);
    }
};

class PlayerEvadeState : MultiMotionState
{
    PlayerEvadeState(Character@ c)
    {
        super(c);
        SetName("EvadeState");
        String prefix = "BM_Movement/";
        AddMotion(prefix + "Evade_Forward_01");
        AddMotion(prefix + "Evade_Right_01");
        AddMotion(prefix + "Evade_Back_01");
        AddMotion(prefix + "Evade_Left_01");
    }
};

class PlayerRedirectState : SingleMotionState
{
    uint redirectEnemyId = M_MAX_UNSIGNED;

    PlayerRedirectState(Character@ c)
    {
        super(c);
        SetName("RedirectState");
        SetMotion("BM_Combat/Redirect");
    }

    void Exit(State@ nextState)
    {
        redirectEnemyId = M_MAX_UNSIGNED;
        SingleMotionState::Exit(nextState);
    }
};

enum AttackStateType
{
    ATTACK_STATE_ALIGN,
    ATTACK_STATE_BEFORE_IMPACT,
    ATTACK_STATE_AFTER_IMPACT,
};

class PlayerAttackState : CharacterState
{
    Array<AttackMotion@>    forwardAttacks;
    Array<AttackMotion@>    leftAttacks;
    Array<AttackMotion@>    rightAttacks;
    Array<AttackMotion@>    backAttacks;

    AttackMotion@           currentAttack;

    int                     state;
    Vector3                 movePerSec;
    Vector3                 predictPosition;
    Vector3                 motionPosition;

    float                   alignTime = 0.3f;

    int                     forwadCloseNum = 0;
    int                     leftCloseNum = 0;
    int                     rightCloseNum = 0;
    int                     backCloseNum = 0;

    int                     slowMotionFrames = 2;

    int                     lastAttackDirection = -1;
    int                     lastAttackIndex = -1;

    bool                    weakAttack = true;
    bool                    slowMotion = false;
    bool                    isInAir = false;
    bool                    lastKill = false;

    PlayerAttackState(Character@ c)
    {
        super(c);
        SetName("AttackState");
        flags = FLAGS_ATTACK;

        //========================================================================
        // FORWARD
        //========================================================================

        // forward weak
        AddAttackMotion(forwardAttacks, "Attack_Close_Weak_Forward", 11, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Weak_Forward_01", 12, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Weak_Forward_02", 12, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Weak_Forward_03", 11, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Weak_Forward_04", 16, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Weak_Forward_05", 12, ATTACK_PUNCH, L_HAND);

        // forward close
        AddAttackMotion(forwardAttacks, "Attack_Close_Forward_02", 14, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Forward_03", 11, ATTACK_KICK, L_FOOT);
        AddAttackMotion(forwardAttacks, "Attack_Close_Forward_04", 19, ATTACK_KICK, R_FOOT);
        AddAttackMotion(forwardAttacks, "Attack_Close_Forward_05", 24, ATTACK_PUNCH, L_ARM);
        AddAttackMotion(forwardAttacks, "Attack_Close_Forward_06", 20, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Forward_07", 15, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Close_Forward_08", 18, ATTACK_PUNCH, R_ARM);
        AddAttackMotion(forwardAttacks, "Attack_Close_Run_Forward", 12, ATTACK_PUNCH, R_HAND);

        // forward far
        AddAttackMotion(forwardAttacks, "Attack_Far_Forward", 25, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Far_Forward_01", 17, ATTACK_KICK, R_FOOT);
        AddAttackMotion(forwardAttacks, "Attack_Far_Forward_02", 21, ATTACK_KICK, L_FOOT);
        AddAttackMotion(forwardAttacks, "Attack_Far_Forward_03", 22, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(forwardAttacks, "Attack_Far_Forward_04", 22, ATTACK_KICK, R_FOOT);
        AddAttackMotion(forwardAttacks, "Attack_Run_Far_Forward", 18, ATTACK_KICK, R_FOOT);

        //========================================================================
        // RIGHT
        //========================================================================
        // right weak
        AddAttackMotion(rightAttacks, "Attack_Close_Weak_Right", 12, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(rightAttacks, "Attack_Close_Weak_Right_01", 10, ATTACK_PUNCH, R_ARM);
        AddAttackMotion(rightAttacks, "Attack_Close_Weak_Right_02", 15, ATTACK_PUNCH, R_HAND);

        // right close
        AddAttackMotion(rightAttacks, "Attack_Close_Right", 16, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(rightAttacks, "Attack_Close_Right_01", 18, ATTACK_PUNCH, R_ARM);
        AddAttackMotion(rightAttacks, "Attack_Close_Right_03", 11, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(rightAttacks, "Attack_Close_Right_04", 19, ATTACK_KICK, R_FOOT);
        AddAttackMotion(rightAttacks, "Attack_Close_Right_05", 15, ATTACK_KICK, L_CALF);
        AddAttackMotion(rightAttacks, "Attack_Close_Right_06", 20, ATTACK_KICK, R_FOOT);
        AddAttackMotion(rightAttacks, "Attack_Close_Right_07", 18, ATTACK_PUNCH, R_ARM);
        AddAttackMotion(rightAttacks, "Attack_Close_Right_08", 18, ATTACK_KICK, L_FOOT);

        // right far
        AddAttackMotion(rightAttacks, "Attack_Far_Right", 25, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(rightAttacks, "Attack_Far_Right_01", 15, ATTACK_KICK, L_CALF);
        // AddAttackMotion(rightAttacks, "Attack_Far_Right_02", 21, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(rightAttacks, "Attack_Far_Right_03", 29, ATTACK_KICK, L_FOOT);
        AddAttackMotion(rightAttacks, "Attack_Far_Right_04", 22, ATTACK_KICK, R_FOOT);

        //========================================================================
        // BACK
        //========================================================================
        // back weak
        AddAttackMotion(backAttacks, "Attack_Close_Weak_Back", 12, ATTACK_PUNCH, L_ARM);
        AddAttackMotion(backAttacks, "Attack_Close_Weak_Back_01", 12, ATTACK_PUNCH, R_HAND);

        AddAttackMotion(backAttacks, "Attack_Close_Back", 11, ATTACK_PUNCH, L_ARM);
        AddAttackMotion(backAttacks, "Attack_Close_Back_01", 16, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(backAttacks, "Attack_Close_Back_02", 18, ATTACK_KICK, L_FOOT);
        AddAttackMotion(backAttacks, "Attack_Close_Back_03", 21, ATTACK_KICK, R_FOOT);
        AddAttackMotion(backAttacks, "Attack_Close_Back_04", 18, ATTACK_KICK, R_FOOT);
        AddAttackMotion(backAttacks, "Attack_Close_Back_05", 14, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(backAttacks, "Attack_Close_Back_06", 15, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(backAttacks, "Attack_Close_Back_07", 14, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(backAttacks, "Attack_Close_Back_08", 17, ATTACK_KICK, L_FOOT);

        // back far
        AddAttackMotion(backAttacks, "Attack_Far_Back", 14, ATTACK_KICK, L_FOOT);
        AddAttackMotion(backAttacks, "Attack_Far_Back_01", 15, ATTACK_KICK, L_FOOT);
        AddAttackMotion(backAttacks, "Attack_Far_Back_02", 22, ATTACK_PUNCH, R_ARM);
        //AddAttackMotion(backAttacks, "Attack_Far_Back_03", 22, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(backAttacks, "Attack_Far_Back_04", 36, ATTACK_KICK, R_FOOT);

        //========================================================================
        // LEFT
        //========================================================================
        // left weak
        AddAttackMotion(leftAttacks, "Attack_Close_Weak_Left", 13, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(leftAttacks, "Attack_Close_Weak_Left_01", 12, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(leftAttacks, "Attack_Close_Weak_Left_02", 13, ATTACK_PUNCH, L_HAND);

        // left close
        AddAttackMotion(leftAttacks, "Attack_Close_Left", 7, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_01", 18, ATTACK_PUNCH, R_HAND);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_02", 13, ATTACK_KICK, R_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_03", 21, ATTACK_KICK, L_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_04", 21, ATTACK_KICK, R_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_05", 15, ATTACK_KICK, L_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_06", 12, ATTACK_KICK, R_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_07", 15, ATTACK_PUNCH, L_HAND);
        AddAttackMotion(leftAttacks, "Attack_Close_Left_08", 20, ATTACK_KICK, L_FOOT);

        // left far
        AddAttackMotion(leftAttacks, "Attack_Far_Left", 19, ATTACK_KICK, L_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Far_Left_01", 22, ATTACK_KICK, R_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Far_Left_02", 22, ATTACK_PUNCH, R_ARM);
        AddAttackMotion(leftAttacks, "Attack_Far_Left_03", 21, ATTACK_KICK, L_FOOT);
        AddAttackMotion(leftAttacks, "Attack_Far_Left_04", 23, ATTACK_KICK, R_FOOT);

        forwardAttacks.Sort();
        leftAttacks.Sort();
        rightAttacks.Sort();
        backAttacks.Sort();

        float min_dist = 2.0f;
        for (uint i=0; i<forwardAttacks.length; ++i)
        {
            if (forwardAttacks[i].impactDist >= min_dist)
                break;
            forwadCloseNum++;
        }
        for (uint i=0; i<rightAttacks.length; ++i)
        {
            if (rightAttacks[i].impactDist >= min_dist)
                break;
            rightCloseNum++;
        }
        for (uint i=0; i<backAttacks.length; ++i)
        {
            if (backAttacks[i].impactDist >= min_dist)
                break;
            backCloseNum++;
        }
        for (uint i=0; i<leftAttacks.length; ++i)
        {
            if (leftAttacks[i].impactDist >= min_dist)
                break;
            leftCloseNum++;
        }

        // if (d_log)
        {
            Print("\n forward attacks(closeNum=" + forwadCloseNum + "): \n");
            DumpAttacks(forwardAttacks);
            Print("\n right attacks(closeNum=" + rightCloseNum + "): \n");
            DumpAttacks(rightAttacks);
            Print("\n back attacks(closeNum=" + backCloseNum + "): \n");
            DumpAttacks(backAttacks);
            Print("\n left attacks(closeNum=" + leftCloseNum + "): \n");
            DumpAttacks(leftAttacks);
        }
    }

    void DumpAttacks(Array<AttackMotion@>@ attacks)
    {
        for (uint i=0; i<attacks.length; ++i)
            Print(attacks[i].motion.animationName + " impactDist=" + String(attacks[i].impactDist));
    }

    void AddAttackMotion(Array<AttackMotion@>@ attacks, const String&in name, int frame, int type, const String&in bName)
    {
        attacks.Push(AttackMotion("BM_Attack/" + name, frame, type, bName));
    }

    ~PlayerAttackState()
    {
        @currentAttack = null;
    }

    void ChangeSubState(int newState)
    {
        Print("PlayerAttackState changeSubState from " + state + " to " + newState);
        state = newState;
    }

    void Update(float dt)
    {
        Motion@ motion = currentAttack.motion;

        Node@ _node = ownner.GetNode();
        Node@ tailNode = _node.GetChild("TailNode", true);
        Node@ attackNode = _node.GetChild(currentAttack.boneName, true);

        if (tailNode !is null && attackNode !is null) {
            tailNode.worldPosition = attackNode.worldPosition;
        }

        float t = ownner.animCtrl.GetTime(motion.animationName);
        if (state == ATTACK_STATE_ALIGN)
        {
            ownner.motion_deltaPosition += movePerSec * dt;
            if (t >= alignTime)
            {
                ChangeSubState(ATTACK_STATE_BEFORE_IMPACT);
                ownner.target.RemoveFlag(FLAGS_NO_MOVE);
            }
        }
        else if (state == ATTACK_STATE_BEFORE_IMPACT)
        {
            if (t > currentAttack.impactTime)
            {
                ChangeSubState(ATTACK_STATE_AFTER_IMPACT);
                AttackImpact();
            }
        }

        if (slowMotion)
        {
            float t_diff = currentAttack.impactTime - t;
            if (t_diff > 0 && t_diff < SEC_PER_FRAME * slowMotionFrames)
                ownner.SetSceneTimeScale(0.1f);
            else
                ownner.SetSceneTimeScale(1.0f);
        }

        ownner.CheckTargetDistance(ownner.target, PLAYER_COLLISION_DIST);

        bool finished = motion.Move(ownner, dt);
        if (finished) {
            Print("Player::Attack finish attack movemont in sub state = " + state);
            ownner.CommonStateFinishedOnGroud();
            return;
        }

        CheckInput(t);
        CharacterState::Update(dt);
    }


    void CheckInput(float t)
    {
        float y_diff = ownner.hipsNode.worldPosition.y - pelvisOrign.y;
        isInAir = y_diff > 0.5f;
        if (isInAir)
            return;

        int addition_frames = slowMotion ? slowMotionFrames : 0;
        bool check_attack = t > currentAttack.impactTime + SEC_PER_FRAME * ( HIT_WAIT_FRAMES + 1 + addition_frames);
        bool check_others = t > currentAttack.impactTime + SEC_PER_FRAME * addition_frames;
        ownner.ActionCheck(check_attack, check_others, check_others, check_others);
    }

    void PickBestMotion(Array<AttackMotion@>@ attacks, int dir)
    {
        Vector3 myPos = ownner.GetNode().worldPosition;
        Vector3 enemyPos = ownner.target.GetNode().worldPosition;
        Vector3 diff = enemyPos - myPos;
        diff.y = 0;
        float toEnenmyDistance = diff.length - PLAYER_COLLISION_DIST;
        if (toEnenmyDistance < 0.0f)
            toEnenmyDistance = 0.0f;
        int bestIndex = 0;
        diff.Normalize();

        int index_start = -1;
        int index_num = 0;

        float min_dist = Max(0.0f, toEnenmyDistance - 2.0f);
        float max_dist = toEnenmyDistance + 2.0f;
        Print("Player attack toEnenmyDistance = " + toEnenmyDistance + "(" + min_dist + "," + max_dist + ")");

        for (uint i=0; i<attacks.length; ++i)
        {
            AttackMotion@ am = attacks[i];
            // Print("am.impactDist=" + am.impactDist);
            if (am.impactDist > max_dist)
                break;

            if (am.impactDist > min_dist)
            {
                if (index_start == -1)
                    index_start = i;
                index_num ++;
            }
        }

        if (index_num == 0)
        {
            if (toEnenmyDistance > attacks[attacks.length - 1].impactDist)
                bestIndex = attacks.length - 1;
            else
                bestIndex = 0;
        }
        else
        {
            bestIndex = index_start + RandomInt(index_num);
            if (lastAttackDirection == dir && bestIndex == lastAttackIndex)
            {
                Print("Repeat Attack index index_num=" + index_num);
                if (index_num > 1)
                {
                    bestIndex ++;
                    int max_index = index_start + index_num - 1;
                    if (bestIndex > max_index)
                        bestIndex = 0;
                }
            }
            lastAttackDirection = dir;
            lastAttackIndex = bestIndex;
        }

        Print("Attack bestIndex="+bestIndex+" index_start="+index_start+" index_num="+index_num);

        @currentAttack = attacks[bestIndex];
        alignTime = currentAttack.impactTime;

        predictPosition = myPos + diff * toEnenmyDistance;
        Print("PlayerAttack dir=" + lastAttackDirection + " index=" + lastAttackIndex + " Pick attack motion = " + currentAttack.motion.animationName);
    }

    void StartAttack()
    {
        Player@ p = cast<Player>(ownner);
        if (ownner.target !is null)
        {
            state = ATTACK_STATE_ALIGN;
            float diff = ownner.ComputeAngleDiff(ownner.target.GetNode());
            int r = DirectionMapToIndex(diff, 4);

            if (d_log)
                Print("Attack-align " + " r-index=" + r + " diff=" + diff);

            if (r == 0)
                PickBestMotion(forwardAttacks, r);
            else if (r == 1)
                PickBestMotion(rightAttacks, r);
            else if (r == 2)
                PickBestMotion(backAttacks, r);
            else if (r == 3)
                PickBestMotion(leftAttacks, r);

            ownner.target.RequestDoNotMove();
            p.lastAttackId = ownner.target.GetNode().id;
        }
        else
        {
            int index = ownner.RadialSelectAnimation(4);
            if (index == 0)
                currentAttack = forwardAttacks[RandomInt(forwadCloseNum)];
            else if (index == 1)
                currentAttack = rightAttacks[RandomInt(rightCloseNum)];
            else if (index == 2)
                currentAttack = backAttacks[RandomInt(backCloseNum)];
            else if (index == 3)
                currentAttack = leftAttacks[RandomInt(leftCloseNum)];
            state = ATTACK_STATE_BEFORE_IMPACT;
            p.lastAttackId = M_MAX_UNSIGNED;

            // lost combo
            p.combo = 0;
            p.StatusChanged();
        }

        Motion@ motion = currentAttack.motion;
        motion.Start(ownner);
        isInAir = false;
        weakAttack = cast<Player>(ownner).combo < MAX_WEAK_ATTACK_COMBO;
        slowMotion = (p.combo >= 3) ? (RandomInt(10) == 1) : false;

        if (ownner.target !is null)
        {
            motionPosition = motion.GetFuturePosition(ownner, currentAttack.impactTime);
            movePerSec = ( predictPosition - motionPosition ) / alignTime;
            movePerSec.y = 0;

            //if (attackEnemy.HasFlag(FLAGS_COUNTER))
            //    slowMotion = true;

            lastKill = p.CheckLastKill();
        }
        else
        {
            weakAttack = false;
            slowMotion = false;
        }

        if (lastKill)
        {
            ownner.SetSceneTimeScale(LAST_KILL_SPEED);
            weakAttack = false;
            slowMotion = false;
        }

        ownner.SetNodeEnabled("TailNode", true);
    }

    void Enter(State@ lastState)
    {
        Print("################## Player::AttackState Enter from " + lastState.name  + " #####################");
        lastKill = false;
        slowMotion = false;
        @currentAttack = null;
        state = ATTACK_STATE_ALIGN;
        movePerSec = Vector3(0, 0, 0);
        StartAttack();
        //ownner.SetSceneTimeScale(0.25f);
        //ownner.SetTimeScale(1.5f);
        CharacterState::Enter(lastState);
    }

    void Exit(State@ nextState)
    {
        CharacterState::Exit(nextState);
        ownner.SetNodeEnabled("TailNode", false);
        //if (nextState !is this)
        //    cast<Player>(ownner).lastAttackId = M_MAX_UNSIGNED;
        if (ownner.target !is null)
            ownner.target.RemoveFlag(FLAGS_NO_MOVE);
        @currentAttack = null;
        ownner.SetSceneTimeScale(1.0f);
        Print("################## Player::AttackState Exit to " + nextState.name  + " #####################");
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        if (currentAttack is null || ownner.target is null)
            return;
        debug.AddLine(ownner.GetNode().worldPosition, ownner.target.GetNode().worldPosition, RED, false);
        debug.AddCross(predictPosition, 0.5f, Color(0.25f, 0.28f, 0.7f), false);
        debug.AddCross(motionPosition, 0.5f, Color(0.75f, 0.28f, 0.27f), false);
    }

    String GetDebugText()
    {
        return " name=" + name + " timeInState=" + String(timeInState) + "\n" +
                "currentAttack=" + currentAttack.motion.animationName +
                " isInAir=" + isInAir +
                " weakAttack=" + weakAttack +
                " slowMotion=" + slowMotion +
                "\n";
    }

    bool CanReEntered()
    {
        return true;
    }

    void AttackImpact()
    {
        Character@ e = ownner.target;

        if (e is null)
            return;

        Node@ _node = ownner.GetNode();
        Vector3 dir = _node.worldPosition - e.GetNode().worldPosition;
        dir.y = 0;
        dir.Normalize();
        Print("PlayerAttackState::" +  e.GetName() + " OnDamage!!!!");

        Node@ n = _node.GetChild(currentAttack.boneName, true);
        Vector3 position = _node.worldPosition;
        if (n !is null)
            position = n.worldPosition;

        int damage = ownner.attackDamage;
        if (lastKill)
            damage = 9999;
        else
            damage = RandomInt(ownner.attackDamage, ownner.attackDamage + 20);
        bool b = e.OnDamage(ownner, position, dir, damage, weakAttack);
        if (!b)
            return;

        ownner.SpawnParticleEffect(position, "Particle/SnowExplosion.xml", 5, 5.0f);
        int sound_type = e.health == 0 ? 1 : 0;
        ownner.PlayRandomSound(sound_type);
        ownner.OnAttackSuccess(e);
    }
};


class PlayerCounterState : CharacterCounterState
{
    Array<Enemy@>   counterEnemies;
    int             lastCounterIndex = -1;
    int             lastCounterDirection = -1;
    bool            bCheckInput = false;
    bool            isInAir = false;

    PlayerCounterState(Character@ c)
    {
        super(c);
        String preFix = "BM_TG_Counter/";
        AddCounterMotions(preFix);
        AddMultiCounterMotions(preFix, true);
    }

    ~PlayerCounterState()
    {
    }

    void Update(float dt)
    {
        if (counterEnemies.length == 0 || currentMotion is null)
        {
            ownner.ChangeState("StandState"); // Something Error Happened
            return;
        }

        CheckInput();
        CharacterCounterState::Update(dt);
    }

    void Enter(State@ lastState)
    {
        Print("############# PlayerCounterState::Enter ##################");

        uint t = time.systemTime;

        CharacterCounterState::Enter(lastState);

        Node@ myNode = ownner.GetNode();
        Vector3 myPos = myNode.worldPosition;
        Quaternion myRot = myNode.worldRotation;

        Print("PlayerCounter-> counterEnemies len=" + counterEnemies.length);
        type = counterEnemies.length;

        // POST_PROCESS
        if (type > 1)
        {
            Vector3 vPos(0, 0, 0);
            int animIndex = 0;
            Array<Motion@>@ tmp_motions = null;

            if (type == 2)
                @tmp_motions = doubleCounterMotions;
            else if (type == 3)
                @tmp_motions = tripleCounterMotions;

            animIndex = RandomInt(tmp_motions.length);
            @currentMotion = tmp_motions[animIndex];

            for (uint i=0; i<counterEnemies.length; ++i)
            {
                Enemy@ e = counterEnemies[i];
                e.ChangeState("CounterState");
                CharacterCounterState@ s = cast<CharacterCounterState>(e.GetState());
                s.index = int(i);
                if (type == 2)
                    @s.currentMotion = s.doubleCounterMotions[animIndex * type + s.index];
                else if (type == 3)
                    @s.currentMotion = s.tripleCounterMotions[animIndex * type + s.index];
                Vector3 ePos = e.GetNode().worldPosition;
                Vector4 t = GetTargetTransform(e.GetNode(), myNode, s.currentMotion, currentMotion);
                s.SetTargetTransform(Vector3(t.x, t.y, t.z), t.w);
                s.ChangeSubState(COUNTER_ALIGNING);
            }
            ChangeSubState(COUNTER_WAITING);
        }
        else if (counterEnemies.length == 1)
        {
            Enemy@ e = counterEnemies[0];
            Node@ eNode = e.GetNode();
            float dAngle = ownner.ComputeAngleDiff(eNode);
            bool isBack = false;
            if (Abs(dAngle) > 90)
                isBack = true;

            e.ChangeState("CounterState");

            int attackType = eNode.vars[ATTACK_TYPE].GetInt();
            CharacterCounterState@ s = cast<CharacterCounterState>(e.GetState());
            if (s is null)
                return;

            Array<Motion@>@ counterMotions = GetCounterMotions(attackType, isBack);
            Array<Motion@>@ eCounterMotions = s.GetCounterMotions(attackType, isBack);

            int idx = RandomInt(counterMotions.length);
            int cur_direction = GetCounterDirection(attackType, isBack);
            if (cur_direction == lastCounterDirection && idx == lastCounterIndex)
                idx = (idx + 1) % counterMotions.length;

            lastCounterDirection = cur_direction;
            lastCounterIndex = idx;

            @currentMotion = counterMotions[idx];
            @s.currentMotion = eCounterMotions[idx];
            Print("Counter-align angle-diff=" + dAngle + " isBack=" + isBack + " name:" + currentMotion.animationName);

            s.ChangeSubState(COUNTER_WAITING);
            ChangeSubState(COUNTER_ALIGNING);

            Vector4 t = GetTargetTransform(myNode, eNode, currentMotion, s.currentMotion);
            SetTargetTransform(Vector3(t.x, t.y, t.z), t.w);
            // ownner.SetSceneTimeScale(0.0f);
        }

        bCheckInput = false;
        Print("PlayerCounterState::Enter time-cost=" + (time.systemTime - t));
    }

    void Exit(State@ nextState)
    {
        Print("############# PlayerCounterState::Exit ##################");
        CharacterCounterState::Exit(nextState);
        if (nextState !is this)
            counterEnemies.Clear();
    }

    String GetDebugText()
    {
        return "current motion=" + currentMotion.animationName + " isInAir=" + isInAir + " bCheckInput=" + bCheckInput + "\n";
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        debug.AddCross(targetPosition, 1.0f, RED, false);
        DebugDrawDirection(debug, ownner.GetNode(), targetRotation, YELLOW);
    }

    void StartAnimating()
    {
        StartCounterMotion();
        for (uint i=0; i<counterEnemies.length; ++i)
        {
            CharacterCounterState@ s = cast<CharacterCounterState>(counterEnemies[i].GetState());
            s.StartCounterMotion();
        }
    }

    void OnAlignTimeOut()
    {
        CharacterCounterState::OnAlignTimeOut();
        StartAnimating();
    }

    void OnWaitingTimeOut()
    {
        CharacterCounterState::OnWaitingTimeOut();
        StartAnimating();
        ownner.SetSceneTimeScale(0.0f);
    }

    void OnAnimationTrigger(AnimationState@ animState, const VariantMap&in eventData)
    {
        CharacterState::OnAnimationTrigger(animState, eventData);
        StringHash name = eventData[NAME].GetStringHash();
        if (name == READY_TO_FIGHT)
            bCheckInput = true;
        else if (name == IMPACT)
        {
            Node@ _node = ownner.GetNode();
            Node@ boneNode = _node.GetChild(eventData[VALUE].GetString(), true);
            Vector3 pos = _node.worldPosition;

            if (boneNode !is null)
            {
                ownner.SpawnParticleEffect(boneNode.worldPosition, "Particle/SnowExplosionFade.xml", 5, 5.0f);
                pos = boneNode.worldPosition;
            }

            ownner.PlayRandomSound(counterEnemies.length > 1 ? 1 : 0);

            Vector3 my_pos = _node.worldPosition;
            if (counterEnemies.length > 1)
            {
                for (uint i=0; i<counterEnemies.length; ++i)
                {
                    Vector3 v = counterEnemies[i].GetNode().worldPosition - my_pos;
                    v.y = 1.0f;
                    v.Normalize();
                    v *= GetRagdollForce();
                    counterEnemies[i].MakeMeRagdoll(v, pos);
                }
            }

            ownner.OnCounterSuccess();
        }
    }

    void CheckInput()
    {
        if (!bCheckInput)
            return;

        float y_diff = ownner.hipsNode.worldPosition.y - pelvisOrign.y;
        isInAir = y_diff > 0.5f;
        if (isInAir)
            return;

        ownner.ActionCheck(true, true, true, true);
    }

    bool CanReEntered()
    {
        return !isInAir && bCheckInput;
    }
};

class PlayerHitState : MultiMotionState
{
    PlayerHitState(Character@ c)
    {
        super(c);
        SetName("HitState");
        String hitPrefix = "BM_Combat_HitReaction/";
        AddMotion(hitPrefix + "HitReaction_Face_Right");
        AddMotion(hitPrefix + "Hit_Reaction_SideLeft");
        AddMotion(hitPrefix + "HitReaction_Back");
        AddMotion(hitPrefix + "Hit_Reaction_SideRight");
    }
};

class PlayerGetUpState : CharacterGetUpState
{
    PlayerGetUpState(Character@ c)
    {
        super(c);
        String prefix = "TG_Getup/";
        AddMotion(prefix + "GetUp_Back");
        AddMotion(prefix + "GetUp_Front");
    }
};

class PlayerDeadState : MultiMotionState
{
    Array<String>   animations;
    int             state = 0;

    PlayerDeadState(Character@ c)
    {
        super(c);
        SetName("DeadState");
        String prefix = "BM_Death_Primers/";
        AddMotion(prefix + "Death_Front");
        AddMotion(prefix + "Death_Side_Left");
        AddMotion(prefix + "Death_Back");
        AddMotion(prefix + "Death_Side_Right");
    }

    void Enter(State@ lastState)
    {
        state = 0;
        MultiMotionState::Enter(lastState);
    }

    void Update(float dt)
    {
        if (state == 0)
        {
            if (motions[selectIndex].Move(ownner, dt))
            {
                state = 1;
                gGame.OnCharacterKilled(null, ownner);
            }
        }
        CharacterState::Update(dt);
    }
};

class PlayerDistractState : SingleMotionState
{
    bool combatReady = false;

    PlayerDistractState(Character@ c)
    {
        super(c);
        SetName("DistractState");
        SetMotion("BM_Attack/CapeDistract_Close_Forward");
        flags = FLAGS_ATTACK;
    }

    void Enter(State@ lastState)
    {
        float targetRotation = ownner.GetTargetAngle();
        ownner.GetNode().worldRotation = Quaternion(0, targetRotation, 0);
        combatReady = false;

        SingleMotionState::Enter(lastState);
    }

    void OnAnimationTrigger(AnimationState@ animState, const VariantMap&in eventData)
    {
        CharacterState::OnAnimationTrigger(animState, eventData);
        StringHash name = eventData[NAME].GetStringHash();
        if (name == IMPACT)
        {
            ownner.PlaySound("Sfx/swing.ogg");

            Player@ p = cast<Player>(ownner);
            Array<Enemy@> enemies;
            p.CommonCollectEnemies(enemies, MAX_DISTRACT_DIR, MAX_DISTRACT_DIST, FLAGS_ATTACK);

            combatReady = true;

            for (uint i=0; i<enemies.length; ++i)
                enemies[i].Distract();
        }
    }

    void Update(float dt)
    {
        if (combatReady)
            ownner.ActionCheck(true, true, true, true);
        SingleMotionState::Update(dt);
    }
};

class PlayerBeatDownStartState : CharacterState
{
    Motion@     motion;

    float       alignTime = 0.2f;
    int         state = 0;
    Vector3     movePerSec;
    Vector3     targetPosition;

    PlayerBeatDownStartState(Character@ c)
    {
        super(c);
        SetName("BeatDownStartState");
        flags = FLAGS_ATTACK;
        @motion = gMotionMgr.FindMotion("BM_Combat/Into_Takedown");
    }

    void Enter(State@ lastState)
    {
        Character@ target = ownner.target;
        float angle = ownner.GetTargetAngle();
        ownner.GetNode().worldRotation = Quaternion(0, angle, 0);

        target.RequestDoNotMove();

        alignTime = 0.2f;
        Vector3 myPos = ownner.GetNode().worldPosition;
        Vector3 enemyPos = target.GetNode().worldPosition;

        float dist = COLLISION_RADIUS*2 + motion.endDistance;
        targetPosition = enemyPos + ownner.GetNode().worldRotation * Vector3(0, 0, -dist);
        movePerSec = ( targetPosition - myPos ) / alignTime;
        movePerSec.y = 0;

        state = 0;

        CharacterState::Enter(lastState);
    }

    void Exit(State@ nextState)
    {
        CharacterState::Exit(nextState);
        if (ownner.target !is null)
            ownner.target.RemoveFlag(FLAGS_NO_MOVE);
    }

    void Update(float dt)
    {
        if (state == 0)
        {
            ownner.MoveTo(ownner.GetNode().worldPosition + movePerSec * dt, dt);

            if (timeInState >= alignTime)
            {
                state = 1;
                motion.Start(ownner);

                Character@ target = ownner.target;
                float angle = ownner.GetTargetAngle();
                target.GetNode().worldRotation = Quaternion(0, angle + 180, 0);
                target.ChangeState("BeatDownStartState");
            }
        }
        else if (state == 1)
        {
            if (motion.Move(ownner, dt)) {
                ownner.ChangeState("BeatDownHitState");
                return;
            }
        }

        CharacterState::Update(dt);
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        if (ownner.target is null)
            return;
        debug.AddLine(ownner.GetNode().worldPosition, ownner.target.GetNode().worldPosition, RED, false);
        debug.AddCross(targetPosition, 1.0f, RED, false);
    }
};

class PlayerBeatDownEndState : MultiMotionState
{
    bool combatReady = false;

    PlayerBeatDownEndState(Character@ c)
    {
        super(c);
        SetName("BeatDownEndState");
        String preFix = "BM_TG_Beatdown/";
        AddMotion(preFix + "Beatdown_Strike_End_01");
        AddMotion(preFix + "Beatdown_Strike_End_02");
        AddMotion(preFix + "Beatdown_Strike_End_03");
        AddMotion(preFix + "Beatdown_Strike_End_04");
    }

    void Enter(State@ lastState)
    {
        combatReady = false;
        selectIndex = PickIndex();
        if (selectIndex >= int(motions.length))
        {
            Print("ERROR: a large animation index=" + selectIndex + " name:" + ownner.GetName());
            selectIndex = 0;
        }

        if (cast<Player>(ownner).CheckLastKill())
            ownner.SetSceneTimeScale(LAST_KILL_SPEED);

        Character@ target = ownner.target;
        if (target !is null)
        {
            Motion@ m1 = motions[selectIndex];
            ThugBeatDownEndState@ state = cast<ThugBeatDownEndState>(target.FindState("BeatDownEndState"));
            Motion@ m2 = state.motions[selectIndex];
            Vector4 t = GetTargetTransform(ownner.GetNode(), target.GetNode(), m1, m2);
            ownner.Transform(Vector3(t.x, t.y, t.z), Quaternion(0, t.w, 0));
            target.GetNode().vars[ANIMATION_INDEX] = selectIndex;
            target.ChangeState("BeatDownEndState");
        }

        if (d_log)
            Print(ownner.GetName() + " state=" + name + " pick " + motions[selectIndex].animationName);
        motions[selectIndex].Start(ownner);

        CharacterState::Enter(lastState);
    }

    void Exit(State@ nextState)
    {
        Print("BeatDownEndState Exit!!");
        ownner.SetSceneTimeScale(1.0f);
        MultiMotionState::Exit(nextState);
    }

    void Update(float dt)
    {
        if (combatReady)
            ownner.ActionCheck(true, true, true, true);
        MultiMotionState::Update(dt);
    }

    int PickIndex()
    {
        return RandomInt(motions.length);
    }

    void OnAnimationTrigger(AnimationState@ animState, const VariantMap&in eventData)
    {
        CharacterState::OnAnimationTrigger(animState, eventData);
        StringHash name = eventData[NAME].GetStringHash();
        if (name == IMPACT)
        {
            Node@ _node = ownner.GetNode();
            Node@ boneNode = _node.GetChild(eventData[VALUE].GetString(), true);
            Vector3 position = _node.worldPosition;
            if (boneNode !is null)
                position = boneNode.worldPosition;
            ownner.SpawnParticleEffect(position, "Particle/SnowExplosionFade.xml", 5, 10.0f);
            ownner.PlayRandomSound(1);
            combatReady = true;
            Character@ target = ownner.target;
            if (target !is null)
            {
                Vector3 dir = _node.worldPosition - target.GetNode().worldPosition;
                dir.y = 0;
                dir.Normalize();
                target.OnDamage(ownner, position, dir, 9999, false);
                ownner.OnAttackSuccess(target);
            }
        }
    }
};

class PlayerBeatDownHitState : MultiMotionState
{
    int beatIndex = 0;
    int beatNum = 0;
    int maxBeatNum = 10;
    int minBeatNum = 5;
    int beatTotal = 0;

    bool combatReady = false;
    bool attackPressed = false;

    float alignTime = 0.1f;
    Vector3 movePerSec;
    Vector3 targetPosition;
    float targetRotation;

    int state = 0;
    bool distToFar = false;

    PlayerBeatDownHitState(Character@ c)
    {
        super(c);
        SetName("BeatDownHitState");
        String preFix = "BM_Attack/";
        AddMotion(preFix + "Beatdown_Test_01");
        AddMotion(preFix + "Beatdown_Test_02");
        AddMotion(preFix + "Beatdown_Test_03");
        AddMotion(preFix + "Beatdown_Test_04");
        AddMotion(preFix + "Beatdown_Test_05");
        AddMotion(preFix + "Beatdown_Test_06");
        flags = FLAGS_ATTACK;
    }

    bool CanReEntered()
    {
        return true;
    }

    void Update(float dt)
    {
        // Print("PlayerBeatDownHitState::Update() " + dt);
        Character@ target = ownner.target;
        if (target is null)
        {
            ownner.CommonStateFinishedOnGroud();
            return;
        }

        if (distToFar)
        {
            ownner.ChangeState("TransitionState");
            PlayerTransitionState@ s = cast<PlayerTransitionState>(ownner.GetState());
            if (s !is null)
            {
                s.nextStateName = name;
                return;
            }
        }

        if (state == 0)
        {
            ownner.MoveTo(ownner.GetNode().worldPosition + movePerSec * dt, dt);

            if (timeInState >= alignTime)
            {
                Print("PlayerBeatDownHitState::Update align time-out");
                state = 1;
                HitStart(false, beatIndex);
                timeInState = 0.0f;
            }
        }
        else if (state == 1)
        {
            if (gInput.IsAttackPressed())
                attackPressed = true;

            if (combatReady && attackPressed)
            {
                ++ beatIndex;
                ++ beatNum;
                beatIndex = beatIndex % motions.length;
                ownner.ChangeState("BeatDownHitState");
                return;
            }

            if (gInput.IsCounterPressed())
            {
                ownner.Counter();
                return;
            }

            if (motions[selectIndex].Move(ownner, dt)) {
                Print("Beat Animation finished");
                OnMotionFinished();
                return;
            }
        }

        CharacterState::Update(dt);
    }

    void HitStart(bool bFirst, int i)
    {
        Character@ target = ownner.target;
        if (target is null)
            return;

        float curDist = ownner.GetTargetDistance();
        Print("HitStart bFirst=" + bFirst + " i=" + i + " current-dist=" + curDist);

        if (curDist >= 12.5f)
        {
            distToFar = true;
            return;
        }

        MultiMotionState@ s = cast<MultiMotionState>(ownner.target.FindState("BeatDownHitState"));
        Motion@ m1 = motions[i];
        Motion@ m2 = s.motions[i];

        Vector3 myPos = ownner.GetNode().worldPosition;
        if (bFirst)
        {
            Vector3 dir = myPos - target.GetNode().worldPosition;
            float e_targetRotation = Atan2(dir.x, dir.z);
            target.GetNode().worldRotation = Quaternion(0, e_targetRotation, 0);
        }

        Vector4 t = GetTargetTransform(ownner.GetNode(), target.GetNode(), m1, m2);
        targetRotation = t.w;
        targetPosition = Vector3(t.x, myPos.y, t.z);
        ownner.GetNode().worldRotation = Quaternion(0, targetRotation, 0);

        if (bFirst)
        {
            state = 0;
            movePerSec = (targetPosition - myPos)/alignTime;
            ownner.SetSceneTimeScale(0.0f);
        }
        else
        {
            state = 1;
            ownner.GetNode().worldPosition = targetPosition;
            target.GetNode().vars[ANIMATION_INDEX] = i;
            motions[i].Start(ownner);
            selectIndex = i;
            target.ChangeState("BeatDownHitState");
        }
    }

    void Enter(State@ lastState)
    {
        Print("========================= BeatDownHitState Enter start ===========================");
        combatReady = false;
        attackPressed = false;
        distToFar = false;
        if (lastState !is this)
        {
            beatNum = 0;
            beatTotal = RandomInt(minBeatNum, maxBeatNum);
        }
        HitStart(lastState !is this, beatIndex);
        CharacterState::Enter(lastState);
        // Print("Beat Total = " + beatTotal + " Num = " + beatNum + " FROM " + lastState.name);
        Print("========================= BeatDownHitState Enter end ===========================");
    }

    void OnAnimationTrigger(AnimationState@ animState, const VariantMap&in eventData)
    {
        CharacterState::OnAnimationTrigger(animState, eventData);
        StringHash name = eventData[NAME].GetStringHash();
        if (name == IMPACT)
        {
            Print("BeatDownHitState On Impact");
            combatReady = true;
            ownner.OnAttackSuccess(ownner.target);
            // Print("Beat Impact Total = " + beatTotal + " Num = " + beatNum);
            if (beatNum >= beatTotal)
            {
                ownner.ChangeState("BeatDownEndState");
            }
        }
    }

    int PickIndex()
    {
        return beatIndex;
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        debug.AddCross(targetPosition, 1.0f, RED, false);
        DebugDrawDirection(debug, ownner.GetNode(), targetRotation, YELLOW);
    }

    String GetDebugText()
    {
        return " name=" + name + " timeInState=" + String(timeInState) + " current motion=" + motions[selectIndex].animationName + "\n" +
        " combatReady=" + combatReady + " attackPressed=" + attackPressed + "\n";
    }
};

class PlayerTransitionState : SingleMotionState
{
    String nextStateName;

    PlayerTransitionState(Character@ c)
    {
        super(c);
        SetName("TransitionState");
        SetMotion("BM_Combat/Into_Takedown");
    }

    void OnMotionFinished()
    {
        Print(ownner.GetName() + " state:" + name + " finshed motion:" + motion.animationName);
        if (!nextStateName.empty)
            ownner.ChangeState(nextStateName);
        else
            ownner.CommonStateFinishedOnGroud();
    }

    void Enter(State@ lastState)
    {
        SingleMotionState::Enter(lastState);
        if (ownner.target !is null)
            ownner.target.RequestDoNotMove();
    }

    void Exit(State@ nextState)
    {
        SingleMotionState::Exit(nextState);
        if (ownner.target !is null)
            ownner.target.RemoveFlag(FLAGS_NO_MOVE);
    }

    String GetDebugText()
    {
        return " name=" + name + " timeInState=" + String(timeInState) + " nextState=" + nextStateName + "\n";
    }
};

class Player : Character
{
    int combo;
    int killed;
    uint lastAttackId = M_MAX_UNSIGNED;

    void ObjectStart()
    {
        side = 1;
        Character::ObjectStart();
        stateMachine.AddState(PlayerStandState(this));
        stateMachine.AddState(PlayerTurnState(this));
        stateMachine.AddState(PlayerMoveState(this));
        stateMachine.AddState(PlayerAttackState(this));
        stateMachine.AddState(PlayerCounterState(this));
        stateMachine.AddState(PlayerEvadeState(this));
        stateMachine.AddState(PlayerHitState(this));
        if (has_redirect)
            stateMachine.AddState(PlayerRedirectState(this));
        stateMachine.AddState(CharacterRagdollState(this));
        stateMachine.AddState(PlayerGetUpState(this));
        stateMachine.AddState(PlayerDeadState(this));
        // stateMachine.AddState(PlayerDistractState(this));
        // stateMachine.AddState(PlayerBeatDownStartState(this));
        stateMachine.AddState(PlayerBeatDownHitState(this));
        stateMachine.AddState(PlayerBeatDownEndState(this));
        stateMachine.AddState(PlayerTransitionState(this));
        stateMachine.AddState(AnimationTestState(this));

        ChangeState("StandState");

        Node@ _node = sceneNode.CreateChild("TailNode");
        TailGenerator@ tail = _node.CreateComponent("TailGenerator");
        tail.material = cache.GetResource("Material", "Materials/Tail.xml");
        tail.width = 0.5f;
        tail.tailNum = 200;
        tail.SetArcValue(0.1f, 10.0f);
        tail.SetStartColor(Color(0.9f,0.5f,0.2f,1), Color(1.0f,1.0f,1.0f,5.0f));
        tail.SetEndColor(Color(1.0f,0.2f,1.0f,1), Color(1.0f,1.0f,1.0f,5.0f));
        // t.endNodeName = "Bip01";
        //tail.enabled = false;
        _node.enabled = false;
        //attackDamage = 100;
    }

    bool Counter()
    {
        Print("Player::Counter");
        PlayerCounterState@ state = cast<PlayerCounterState>(stateMachine.FindState("CounterState"));
        if (state is null)
            return false;

        int len = PickCounterEnemy(state.counterEnemies);
        if (len == 0)
            return false;

        ChangeState("CounterState");
        return true;
    }

    bool Evade()
    {
        Print("Player::Evade()");

        Enemy@ redirectEnemy = null;
        if (has_redirect)
            @redirectEnemy = PickRedirectEnemy();

        if (redirectEnemy !is null)
        {
            PlayerRedirectState@ s = cast<PlayerRedirectState>(stateMachine.FindState("RedirectState"));
            s.redirectEnemyId = redirectEnemy.GetNode().id;
            ChangeState("RedirectState");
            redirectEnemy.Redirect();
        }
        else
        {
            // if (!gInput.IsLeftStickInDeadZone() && gInput.IsLeftStickStationary())
            {
                int index = RadialSelectAnimation(4);
                Print("Evade Index = " + index);
                sceneNode.vars[ANIMATION_INDEX] = index;
                ChangeState("EvadeState");
            }
        }

        return true;
    }

    void CommonStateFinishedOnGroud()
    {
        if (health > 0)
        {
            if (gInput.IsLeftStickInDeadZone() && gInput.IsLeftStickStationary())
                ChangeState("StandState");
            else
                ChangeState("MoveState");
        }
    }

    float GetTargetAngle()
    {
        return gInput.m_leftStickAngle + gCameraMgr.GetCameraAngle();
    }

    bool OnDamage(GameObject@ attacker, const Vector3&in position, const Vector3&in direction, int damage, bool weak = false)
    {
        if (!CanBeAttacked()) {
            if (d_log)
                Print("OnDamage failed because I can no be attacked " + GetName());
            return false;
        }

        health -= damage;
        health = Max(0, health);
        SetHealth(health);

        int index = RadialSelectAnimation(attacker.GetNode(), 4);
        Print("Player::OnDamage RadialSelectAnimation index=" + index);

        if (health <= 0)
            OnDead();
        else
        {
            sceneNode.vars[ANIMATION_INDEX] = index;
            ChangeState("HitState");
        }

        StatusChanged();
        return true;
    }

    void OnAttackSuccess(Character@ target)
    {
        if (target is null)
        {
            Print("Player::OnAttackSuccess target is null");
            return;
        }

        combo ++;
        Print("OnAttackSuccess combo add to " + combo);

        if (target.health == 0)
        {
            killed ++;
            Print("killed add to " + killed);
            gGame.OnCharacterKilled(this, target);
        }

        StatusChanged();
    }

    void OnCounterSuccess()
    {
        combo ++;
        Print("OnCounterSuccess combo add to " + combo);
        StatusChanged();
    }

    void StatusChanged()
    {
        const int speed_up_combo = 10;
        float fov = BASE_FOV;

        if (combo < speed_up_combo)
        {
            SetTimeScale(1.0f);
        }
        else
        {
            int max_comb = 60;
            int c = Min(combo, max_comb);
            float a = float(c)/float(max_comb);
            const float max_time_scale = 1.25f;
            float time_scale = Lerp(1.0f, max_time_scale, a);
            SetTimeScale(time_scale);
            const float max_fov = 60;
            fov = Lerp(BASE_FOV, max_fov, a);
        }
        VariantMap data;
        data[TARGET_FOV] = fov;
        SendEvent("CameraEvent", data);
        gGame.OnPlayerStatusUpdate(this);
    }

    //====================================================================
    //      SMART ENEMY PICK FUNCTIONS
    //====================================================================
    int PickCounterEnemy(Array<Enemy@>@ counterEnemies)
    {
        EnemyManager@ em = cast<EnemyManager>(GetScene().GetScriptObject("EnemyManager"));
        if (em is null)
            return 0;

        counterEnemies.Clear();
        Vector3 myPos = sceneNode.worldPosition;
        for (uint i=0; i<em.enemyList.length; ++i)
        {
            Enemy@ e = em.enemyList[i];
            if (!e.CanBeCountered())
            {
                if (d_log)
                    Print(e.GetName() + " can not be countered");
                continue;
            }
            Vector3 posDiff = e.sceneNode.worldPosition - myPos;
            posDiff.y = 0;
            float distSQR = posDiff.lengthSquared;
            if (distSQR > MAX_COUNTER_DIST * MAX_COUNTER_DIST)
            {
                if (d_log)
                    Print(e.GetName() + " counter distance too long" + distSQR);
                continue;
            }
            counterEnemies.Push(e);
        }

        Print("PickCounterEnemy ret=" + counterEnemies.length);
        return counterEnemies.length;
    }

    Enemy@ PickRedirectEnemy()
    {
        EnemyManager@ em = cast<EnemyManager>(GetScene().GetScriptObject("EnemyManager"));
        if (em is null)
            return null;

        Enemy@ redirectEnemy = null;
        const float bestRedirectDist = 5;
        const float maxRedirectDist = 7;
        const float maxDirDiff = 45;

        float myDir = GetCharacterAngle();
        float bestDistDiff = 9999;

        for (uint i=0; i<em.enemyList.length; ++i)
        {
            Enemy@ e = em.enemyList[i];
            if (!e.CanBeRedirected()) {
                Print("Enemy " + e.GetName() + " can not be redirected.");
                continue;
            }

            float enemyDir = e.GetCharacterAngle();
            float totalDir = Abs(AngleDiff(myDir - enemyDir));
            float dirDiff = Abs(totalDir - 180);
            Print("Evade-- myDir=" + myDir + " enemyDir=" + enemyDir + " totalDir=" + totalDir + " dirDiff=" + dirDiff);
            if (dirDiff > maxDirDiff)
                continue;

            float dist = GetTargetDistance(e.sceneNode);
            if (dist > maxRedirectDist)
                continue;

            dist = Abs(dist - bestRedirectDist);
            if (dist < bestDistDiff)
            {
                @redirectEnemy = e;
                dist = bestDistDiff;
            }
        }

        return redirectEnemy;
    }

    Enemy@ CommonPickEnemy(float maxDiffAngle, float maxDiffDist, int flags, bool checkBlock, bool checkLastAttack)
    {
        uint t = time.systemTime;
        Scene@ _scene = GetScene();
        EnemyManager@ em = cast<EnemyManager>(_scene.GetScriptObject("EnemyManager"));
        if (em is null)
            return null;

        // Find the best enemy
        Vector3 myPos = sceneNode.worldPosition;
        Vector3 myDir = sceneNode.worldRotation * Vector3(0, 0, 1);
        float myAngle = Atan2(myDir.x, myDir.z);
        float cameraAngle = gCameraMgr.GetCameraAngle();
        float targetAngle = gInput.m_leftStickAngle + cameraAngle;
        em.scoreCache.Clear();

        Enemy@ attackEnemy = null;
        for (uint i=0; i<em.enemyList.length; ++i)
        {
            Enemy@ e = em.enemyList[i];
            if (!e.HasFlag(flags))
            {
                if (d_log)
                    Print(e.GetName() + " no flag: " + flags);
                em.scoreCache.Push(-1);
                continue;
            }

            Vector3 posDiff = e.GetNode().worldPosition - myPos;
            posDiff.y = 0;
            int score = 0;
            float dist = posDiff.length - PLAYER_COLLISION_DIST;

            if (dist > maxDiffDist)
            {
                if (d_log)
                    Print(e.GetName() + " far way from player");
                em.scoreCache.Push(-1);
                continue;
            }

            float enemyAngle = Atan2(posDiff.x, posDiff.z);
            float diffAngle = targetAngle - enemyAngle;
            diffAngle = AngleDiff(diffAngle);

            if (Abs(diffAngle) > maxDiffAngle)
            {
                if (d_log)
                    Print(e.GetName() + " diffAngle=" + diffAngle + " too large");
                em.scoreCache.Push(-1);
                continue;
            }

            if (d_log)
                Print("enemyAngle="+enemyAngle+" targetAngle="+targetAngle+" diffAngle="+diffAngle);

            int threatScore = 0;
            if (dist < 1.0f + COLLISION_SAFE_DIST)
            {
                CharacterState@ state = cast<CharacterState>(e.GetState());
                threatScore += int(state.GetThreatScore() * THREAT_SCORE);
            }
            int angleScore = int((180.0f - Abs(diffAngle))/180.0f * ANGLE_SCORE);
            int distScore = int((maxDiffDist - dist) / maxDiffDist * DIST_SCORE);
            score += distScore;
            score += angleScore;
            score += threatScore;

            if (checkLastAttack)
            {
                if (lastAttackId == e.sceneNode.id)
                {
                    if (diffAngle <= LAST_ENEMY_ANGLE)
                        score += LAST_ENEMY_SCORE;
                }
            }

            em.scoreCache.Push(score);

            if (d_log)
                Print("Enemy " + e.sceneNode.name + " dist=" + dist + " diffAngle=" + diffAngle + " score=" + score);
        }

        int bestScore = 0;
        for (uint i=0; i<em.scoreCache.length;++i)
        {
            int score = em.scoreCache[i];
            if (score >= bestScore) {
                bestScore = score;
                @attackEnemy = em.enemyList[i];
            }
        }

        if (attackEnemy !is null && checkBlock)
        {
            Print("CommonPicKEnemy-> attackEnemy is " + attackEnemy.GetName());
            Vector3 v_pos = sceneNode.worldPosition;
            v_pos.y = CHARACTER_HEIGHT / 2;
            Vector3 e_pos = attackEnemy.GetNode().worldPosition;
            e_pos.y = v_pos.y;
            Vector3 dir = e_pos - v_pos;
            float len = dir.length;
            dir.Normalize();
            Ray ray;
            ray.Define(v_pos, dir);
            PhysicsRaycastResult result = sceneNode.scene.physicsWorld.RaycastSingle(ray, len, COLLISION_LAYER_CHARACTER);
            if (result.body !is null)
            {
                Node@ n = result.body.node.parent;
                Enemy@ e = cast<Enemy>(n.scriptObject);
                if (e !is null && e !is attackEnemy && e.HasFlag(FLAGS_ATTACK))
                {
                    Print("Find a block enemy " + e.GetName() + " before " + attackEnemy.GetName());
                    @attackEnemy = e;
                }
            }
        }

        Print("CommonPicKEnemy() time-cost = " + (time.systemTime - t) + " ms");
        return attackEnemy;
    }

    void CommonCollectEnemies(Array<Enemy@>@ enemies, float maxDiffAngle, float maxDiffDist, int flags)
    {
        enemies.Clear();

        uint t = time.systemTime;
        Scene@ _scene = GetScene();
        EnemyManager@ em = cast<EnemyManager>(_scene.GetScriptObject("EnemyManager"));
        if (em is null)
            return;

        Vector3 myPos = sceneNode.worldPosition;
        Vector3 myDir = sceneNode.worldRotation * Vector3(0, 0, 1);
        float myAngle = Atan2(myDir.x, myDir.z);
        float cameraAngle = gCameraMgr.GetCameraAngle();
        float targetAngle = gInput.m_leftStickAngle + cameraAngle;

        for (uint i=0; i<em.enemyList.length; ++i)
        {
            Enemy@ e = em.enemyList[i];
            if (!e.HasFlag(flags))
                continue;
            Vector3 posDiff = e.GetNode().worldPosition - myPos;
            posDiff.y = 0;
            int score = 0;
            float dist = posDiff.length - PLAYER_COLLISION_DIST;
            if (dist > maxDiffDist)
                continue;
            float enemyAngle = Atan2(posDiff.x, posDiff.z);
            float diffAngle = targetAngle - enemyAngle;
            diffAngle = AngleDiff(diffAngle);
            if (Abs(diffAngle) > maxDiffAngle)
                continue;
            enemies.Push(e);
        }

        Print("CommonCollectEnemies() len=" + enemies.length + " time-cost = " + (time.systemTime - t) + " ms");
    }

    String GetDebugText()
    {
        return Character::GetDebugText() +  "health=" + health + " flags=" + flags +
              " combo=" + combo + " killed=" + killed + " timeScale=" + timeScale +
              " tAngle=" + GetTargetAngle() + "\n";
    }

    void Reset()
    {
        SetSceneTimeScale(1.0f);
        Character::Reset();
        combo = 0;
        killed = 0;
        gGame.OnPlayerStatusUpdate(this);
        VariantMap data;
        data[TARGET_FOV] = BASE_FOV;
        SendEvent("CameraEvent", data);
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        Character::DebugDraw(debug);
        //debug.AddCircle(sceneNode.worldPosition, Vector3(0, 1, 0), KEEP_DIST_WITHIN_PLAYER + COLLISION_RADIUS, RED, 32, false);
    }

    void ActionCheck(bool bAttack, bool bDistract, bool bCounter, bool bEvade)
    {
        if (bAttack && gInput.IsAttackPressed())
            Attack();

        if (bDistract && gInput.IsDistractPressed())
            Distract();

        if (bCounter && gInput.IsCounterPressed())
            Counter();

        if (bEvade && gInput.IsEvadePressed())
            Evade();
    }

    bool Attack()
    {
        Print("Do--Attack--->");
        Enemy@ e = CommonPickEnemy(90, 25.0f, FLAGS_ATTACK, true, true);
        SetTarget(e);
        if (e !is null && e.HasFlag(FLAGS_STUN))
            ChangeState("BeatDownHitState");
        else
            ChangeState("AttackState");
        return true;
    }

    bool Distract()
    {
        Print("Do--Distract--->");
        Enemy@ e = CommonPickEnemy(60, 25.0f, FLAGS_ATTACK | FLAGS_STUN, true, true);
        if (e is null)
            return false;
        SetTarget(e);
        ChangeState("BeatDownHitState");
        return true;
    }

    bool CheckLastKill()
    {
        EnemyManager@ em = cast<EnemyManager>(sceneNode.scene.GetScriptObject("EnemyManager"));
        if (em is null)
            return false;

        int alive = em.GetNumOfEnemyAlive();
        Print("CheckLastKill() alive=" + alive);
        if (alive == 1)
        {
            VariantMap data;
            data[NODE] = target.GetNode().id;
            data[NAME] = CHANGE_STATE;
            data[VALUE] = StringHash("Death");
            SendEvent("CameraEvent", data);
            return true;
        }
        return false;
    }

    void SetTarget(Character@ t)
    {
        if (target is t)
            return;
        if (target !is null)
            target.RemoveFlag(FLAGS_NO_MOVE);
        Character::SetTarget(t);
    }
};
