# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the app
flutter run

# Run with device selection
flutter devices
flutter run -d <device_id>

# Code analysis
flutter analyze
flutter format .
flutter pub get

# Clean build
flutter clean && flutter pub get
```

## Architecture Overview

### Project Structure

```
lib/
├── api/              # API layer - REST endpoint definitions
├── components/       # Reusable UI components
├── hooks/            # flutter_hooks custom hooks
├── http/             # HTTP client (Dio) and interceptors
├── models/           # Data models with fromJson/toJson
├── router/           # go_router configuration
├── service/          # External services (AI, MCP)
├── store/            # State management (signals pattern)
├── styles/           # Shared styles
├── theme/            # Design system (colors, spacing, typography, shadows)
├── utils/            # Utilities
└── views/            # Screen-level widgets
```

### Key Patterns

**State Management**: Uses `signals` package for reactive state
- `Signal<T>` for reactive values
- `computed()` for derived state
- `useSignalValue()` in HookWidgets for auto-rebuild

**HTTP**: Dio-based client in `lib/http/index.dart`
- Base URL: `http://192.168.1.17:18084`
- Auto-injects Bearer token from `UserStore`
- Custom `ReqOptions` wrapper for requests
- Response format: `{ code, msg, data }`

**Routing**: go_router with ShellRoute for tab navigation
- Main tabs under `/home/tab1` through `/home/tab4`
- Independent pages outside ShellRoute (e.g., `/check-in`, `/geo-fence`)
- Auth redirect logic in router config

**UI Design System**: Spring colors theme (`lib/theme/`)
- `useTheme()` hook returns `ThemeColors` with `isDark`, `textPrimary`, `cardBackground`, etc.
- `AppSpacing` for 4px grid spacing (xs=4, sm=8, md=12, lg=16, xl=20, xxl=24)
- `AppShadows` for card, light, heavy shadows
- `AppTypography` for text styles

**Skeleton Loading**: Custom `useSkeleton` hook pattern
```dart
final skeleton = useSkeleton<T>(
  emptyMsg: '暂无数据',
  isEmpty: (data) => data.isEmpty,
  request: () async => await Api.fetch(),
);
// In widget: SkeletonView.fromHook(skeleton, (data) => ...)
```

### Authentication Flow

1. `UserStore.init()` loads token from SharedPreferences on app start
2. Token stored in `_tokenSignal`, status in `_statusSignal`
3. Router redirects unauthenticated users to `/login`
4. Login sets token via `UserStore.login(token: ...)`
5. HTTP interceptor adds `Authorization: Bearer <token>` header

### API Pattern

API files in `lib/api/` follow this structure:
```dart
class XxxApi {
  static Future<T> getXxx({params}) async {
    final response = await http.request(
      ReqOptions(path: '/endpoint', method: 'GET', params: {...}),
    );
    return Model.fromJson(response);
  }
}
```

### Design System Summary

| Category | Value |
|----------|-------|
| Primary colors | mintGreen (#10B981), skyBlue (#3B82F6), sproutYellow (#F59E0B), cherryRed (#DC2626) |
| Spacing | 4px grid: xs=4, sm=8, md=12, lg=16, xl=20, xxl=24 |
| Radius | small=10, medium=12, large=16, xLarge=24 |
| Font | Roboto, sizes: 12-20px |
| Shadows | card (blur=10), light (blur=8), heavy (blur=20) |

## Skills

Custom skills available via `/skill-name` commands:
- `/ui-design` or `/ui` - UI design system reference
- `/flutter-architecting-apps` - Layered architecture guidance
- `/flutter-handling-http-and-json` - HTTP/JSON patterns
- `/flutter-building-layouts` - Layout patterns
- `/flutter-building-forms` - Form patterns
- `/flutter-implementing-navigation-and-routing` - Routing patterns
- `/flutter-adding-home-screen-widgets` - Home screen widgets
