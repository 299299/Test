// ==============================================
//
//    Vehicle Base Class
//
// ==============================================

class VehicleInteractivingState : Interactable_InteractivingState
{
    VehicleInteractivingState(Interactable@ i)
    {
        super(i);
    }

    void Update(float dt)
    {
        if (timeInState > 1)
        {
            ownner.ChangeState("IdleState");
            return;
        }

        Interactable_InteractivingState::Update(dt);
    }
};


class Vehicle : Interactable
{
    void ObjectStart()
    {
        Interactable::ObjectStart();

        type = kInteract_Vehicle;
        collectText = FilterName(sceneNode.name);
        interactText = collectText + "  ....";
    }

    void CreatePhysics()
    {
        RigidBody@ body = sceneNode.CreateComponent("RigidBody");
        body.collisionLayer = COLLISION_LAYER_PROP;
        body.collisionMask = COLLISION_LAYER_LANDSCAPE | COLLISION_LAYER_CHARACTER | COLLISION_LAYER_RAGDOLL | COLLISION_LAYER_RAYCAST | COLLISION_LAYER_PROP;
        CollisionShape@ shape = sceneNode.CreateComponent("CollisionShape");
        shape.SetBox(size, GetOffset());
    }

    void AddStates()
    {
        Interactable::AddStates();
        stateMachine.AddState(VehicleInteractivingState(this));
    }
}
