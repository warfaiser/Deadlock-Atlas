# Структура сцен Velocity Atlas

Деревья узлов сгенерированы прямо из `.tscn`-файлов (`tools/`), поэтому они
соответствуют коду. Здесь же — сигналы `[connection]` и назначение ключевых узлов.

## `scenes/MainMenu.tscn`

```
MainMenu  (Control)   ← res://scripts/ui/main_menu.gd
Background  (SubViewportContainer)
    PreviewViewport  (SubViewport)
        FillLight  (OmniLight3D)
        KeyLight  (DirectionalLight3D)
        PreviewCamera  (Camera3D)
        ShowCar  (<res://assets/models/Car.tscn>)
        WorldEnvironment  (WorldEnvironment)
ModePanel  (PanelContainer)
    ModeBox  (VBoxContainer)
        BotsLabel  (Label)
        BotsOption  (OptionButton)
        CarInfoLabel  (Label)
        DifficultyLabel  (Label)
        DifficultyOption  (OptionButton)
        ModeLabel  (Label)
        ModeOption  (OptionButton)
        Spacer  (Control)
        TrackInfoLabel  (Label)
Panel  (PanelContainer)
    VBox  (VBoxContainer)
        CarSelectButton  (Button)
        ExitButton  (Button)
        PlayButton  (Button)
        SettingsButton  (Button)
        TrackSelectButton  (Button)
SettingsPanel  (<res://scenes/SettingsPanel.tscn>)
SubtitleLabel  (Label)
TitleLabel  (Label)
VersionLabel  (Label)
```

## `scenes/CarSelect.tscn`

```
CarSelect  (Control)   ← res://scripts/ui/car_select.gd
BottomBar  (HBoxContainer)
    BackButton  (Button)
    NextButton  (Button)
    PrevButton  (Button)
    SelectButton  (Button)
Header  (Label)
ListPanel  (PanelContainer)
    ListBox  (VBoxContainer)
PreviewArea  (PanelContainer)
    PreviewView  (SubViewportContainer)
        PreviewViewport  (SubViewport)
            FillLight  (OmniLight3D)
            KeyLight  (DirectionalLight3D)
            PreviewCamera  (Camera3D)
            ShowCar  (<res://assets/models/Car.tscn>)
            WorldEnvironment  (WorldEnvironment)
StatsPanel  (PanelContainer)
    StatsBox  (VBoxContainer)
        AccelRow  (HBoxContainer)
            Bar  (ProgressBar)
            RowName  (Label)
        BrakesRow  (HBoxContainer)
            Bar  (ProgressBar)
            RowName  (Label)
        CarDescLabel  (Label)
        CarNameLabel  (Label)
        GripRow  (HBoxContainer)
            Bar  (ProgressBar)
            RowName  (Label)
        HandlingRow  (HBoxContainer)
            Bar  (ProgressBar)
            RowName  (Label)
        MassLabel  (Label)
        SpeedRow  (HBoxContainer)
            Bar  (ProgressBar)
            RowName  (Label)
```

## `scenes/TrackSelect.tscn`

```
TrackSelect  (Control)   ← res://scripts/ui/track_select.gd
BottomBar  (HBoxContainer)
    BackButton  (Button)
    ResetButton  (Button)
    StartButton  (Button)
CardsPanel  (PanelContainer)
    CardsScroll  (ScrollContainer)
        CardsBox  (HBoxContainer)
DetailPanel  (PanelContainer)
    DetailBox  (HBoxContainer)
        InfoBox  (VBoxContainer)
            DescLabel  (Label)
            DifficultyLabel  (Label)
            LapsLabel  (Label)
            LengthLabel  (Label)
            RecordLabel  (Label)
            TrackNameLabel  (Label)
        PreviewRect  (TextureRect)
Header  (Label)
```

## `scenes/Race.tscn`

```
Race  (Node3D)   ← res://scripts/race_manager.gd
Cars  (Node3D)
HUD  (CanvasLayer)   ← res://scripts/ui/hud.gd
    Root  (Control)
        CountdownLabel  (Label)
        MessageLabel  (Label)
        MinimapPanel  (PanelContainer)
            MinimapView  (SubViewportContainer)
                MinimapViewport  (SubViewport)
                    MinimapCamera  (Camera3D)
        MotionBlur  (ColorRect)
        ProgressBar  (ProgressBar)
        RivalsPanel  (PanelContainer)
            RivalsBox  (VBoxContainer)
        Speedo  (Control)   ← res://scripts/ui/speedometer.gd
        TopLeft  (PanelContainer)
            InfoBox  (VBoxContainer)
                BestLabel  (Label)
                LapLabel  (Label)
                PenaltyLabel  (Label)
                PositionLabel  (Label)
                TimeLabel  (Label)
LapTimers  (Node)
PauseMenu  (<res://scenes/PauseMenu.tscn>)
TrackRoot  (Node3D)
```

## `scenes/PauseMenu.tscn`

```
PauseMenu  (CanvasLayer)   ← res://scripts/ui/pause_menu.gd
Dimmer  (ColorRect)
Panel  (PanelContainer)
    VBox  (VBoxContainer)
        HintLabel  (Label)
        MenuButton  (Button)
        QuitButton  (Button)
        RestartButton  (Button)
        ResumeButton  (Button)
        SettingsButton  (Button)
        TitleLabel  (Label)
SettingsPanel  (<res://scenes/SettingsPanel.tscn>)
```

## `scenes/SettingsPanel.tscn`

```
SettingsPanel  (Control)   ← res://scripts/ui/settings_panel.gd
Panel  (PanelContainer)
    VBox  (VBoxContainer)
        BlurCheck  (CheckButton)
        CloseButton  (Button)
        FogCheck  (CheckButton)
        FullscreenCheck  (CheckButton)
        MasterRow  (HBoxContainer)
            MasterName  (Label)
            MasterSlider  (HSlider)
            MasterValue  (Label)
        MsaaRow  (HBoxContainer)
            MsaaName  (Label)
            MsaaOption  (OptionButton)
        MusicRow  (HBoxContainer)
            MusicName  (Label)
            MusicSlider  (HSlider)
            MusicValue  (Label)
        QualityRow  (HBoxContainer)
            QualityName  (Label)
            QualityOption  (OptionButton)
        ResetButton  (Button)
        SfxRow  (HBoxContainer)
            SfxName  (Label)
            SfxSlider  (HSlider)
            SfxValue  (Label)
        ShadowsCheck  (CheckButton)
        SsrCheck  (CheckButton)
        TitleLabel  (Label)
```

## `scenes/Results.tscn`

```
Results  (Control)   ← res://scripts/ui/results_screen.gd
BottomBar  (HBoxContainer)
    MenuButton  (Button)
    NextButton  (Button)
    ReplayButton  (Button)
HeaderPanel  (PanelContainer)
    HeaderBox  (VBoxContainer)
        TitleLabel  (Label)
SummaryPanel  (PanelContainer)
    SummaryBox  (VBoxContainer)
        BestLabel  (Label)
        PenaltyLabel  (Label)
        PositionLabel  (Label)
        RecordLabel  (Label)
        TotalLabel  (Label)
TablePanel  (PanelContainer)
    TableScroll  (ScrollContainer)
        TableBox  (VBoxContainer)
```

## `assets/models/Car.tscn`

```
Car  (VehicleBody3D)
BodyVisual  (Node3D)
    Cabin  (MeshInstance3D)
    Chassis  (MeshInstance3D)
    HeadlightL  (OmniLight3D)
    HeadlightR  (OmniLight3D)
    Spoiler  (MeshInstance3D)
    Taillight  (OmniLight3D)
CameraMount  (Marker3D)
CollisionShape3D  (CollisionShape3D)
EngineAudio  (AudioStreamPlayer3D)
ImpactSparks  (GPUParticles3D)
SquealAudio  (AudioStreamPlayer3D)
TireSmoke  (GPUParticles3D)
WheelFL  (VehicleWheel3D)
    WheelMesh  (MeshInstance3D)
WheelFR  (VehicleWheel3D)
    WheelMesh  (MeshInstance3D)
WheelRL  (VehicleWheel3D)
    WheelMesh  (MeshInstance3D)
WheelRR  (VehicleWheel3D)
    WheelMesh  (MeshInstance3D)
```

## `assets/models/CarPlayer.tscn`

```
CarPlayer  (<res://assets/models/Car.tscn>)   ← res://scripts/car_player.gd
ChaseRig  (SpringArm3D)
    Camera3D  (Camera3D)
```

## `assets/models/CarAI.tscn`

```
CarAI  (<res://assets/models/Car.tscn>)   ← res://scripts/car_ai.gd
```

## `assets/models/Track.tscn`

```
Track  (Node3D)   ← res://scripts/world/track_builder.gd
Checkpoints  (Node3D)
EnvironmentController  (Node)   ← res://scripts/world/environment_controller.gd
Ground  (MeshInstance3D)
RacePath  (Path3D)
Road  (MeshInstance3D)
RoadCollision  (StaticBody3D)
    CollisionShape3D  (CollisionShape3D)
Scenery  (MultiMeshInstance3D)
StartLine  (MeshInstance3D)
Sun  (DirectionalLight3D)
WorldEnvironment  (WorldEnvironment)
```
