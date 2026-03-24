# ThingStruct Maintenance Guide

## Read Order
- `ThingStruct/CoreShared`: pure rules and shared models
- `ThingStruct/ThingStructStore.swift`: app state, screen queries, user commands
- `ThingStruct/ThingStructApp.swift`: app launch, root UI, quick actions, external routing
- `ThingStructWidgetExtension`: widget rendering and widget-only entry points

## Where Changes Go
- Change planning rules, validation, template logic, or time resolution in `Engine` files.
- Change what a screen needs to render in `ScreenModels` and the presentation helpers.
- Change user-triggered app behavior in `ThingStructStore`.
- Change deep links, quick actions, widget buttons, notifications, or live activity wiring in the app/widget entry files.

## When To Add A File
- Add a new file only when one file is carrying two separate responsibilities.
- Do not create a new file for a tiny helper that is only used by one feature screen or one entry point.
- Prefer adding a `MARK` section and a private helper before splitting a file.

## When To Avoid Abstraction
- Do not add a protocol, factory, manager, or service container unless there is a second real implementation today.
- Prefer a concrete type with explicit parameters over a hidden dependency layer.
- Prefer one obvious write path over multiple convenience entry points.

## Safe Refactor Checklist
- Keep `DayPlanEngine` and `TemplateEngine` pure.
- Keep repository code limited to loading, saving, and atomic document mutation.
- Keep route parsing outside `ThingStructStore`.
- Run `swift test` after core changes.
- Run an Xcode build after app or widget entry changes.
