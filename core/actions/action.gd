class_name Action
extends RefCounted
## Abstract base for player intents. Presentation and AI construct Actions
## and hand them to Rules.validate() / Rules.apply(); nothing else mutates
## GameState. Concrete actions: UnitAction, EndTurnAction (BuildAction and
## PowerAction arrive with the economy and CO milestones).
