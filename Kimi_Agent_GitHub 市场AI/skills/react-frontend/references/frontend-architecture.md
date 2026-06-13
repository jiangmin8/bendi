# Frontend Architecture Detail

## Table of Contents
1. [Component Hierarchy](#component-hierarchy)
2. [State Management](#state-management)
3. [Key Components](#key-components)
4. [Responsive Design](#responsive-design)

## Component Hierarchy

```
App
  -> AuthProvider (context)
    -> Layout
      -> Sidebar (collapsible on mobile)
        -> ChatHistory (conversation list)
        -> ModelSelector
        -> SettingsLink
      -> MainContent
        -> ChatView (default)
          -> MessageList
            -> MessageItem (user/assistant/tool)
              -> MarkdownRenderer
              -> ToolCallCard (if tool call)
          -> MessageInput
            -> Textarea (auto-resize)
            -> SendButton
            -> ToolToggle (enable/disable tools)
        -> CompareView
          -> ComparePanel x N (2-4 models)
        -> MemoryView
          -> SearchBar
          -> MemoryList
        -> SettingsView
          -> AuthSettings
          -> ModelConfig (API keys)
          -> ToolPermissions
```

## State Management

```typescript
// Global state (React Context or Zustand)
interface AppState {
  // Auth
  user: User | null;
  token: string | null;
  
  // Chat
  messages: Message[];
  isStreaming: boolean;
  selectedModel: string;       // "gpt-4", "claude-3", etc.
  selectedTools: string[];     // enabled tools
  
  // Compare
  compareModels: string[];     // selected for comparison
  compareResults: CompareResult[];
  
  // Memory
  memoryQuery: string;
  memoryResults: MemoryItem[];
}
```

## Key Components

### MessageItem

Renders different styles for:
- **User**: Right-aligned, different background
- **Assistant**: Left-aligned, markdown support
- **Tool Call**: Collapsible card with tool name, args, result
- **System**: Subtle styling, informational

### ToolCallCard

```typescript
interface ToolCallCardProps {
  toolName: string;
  arguments: Record<string, any>;
  result: string | null;      // null while executing
  status: "pending" | "running" | "success" | "error";
  duration?: number;           // ms
}
```

### ComparePanel

- Fixed-width columns (2=50%, 3=33%, 4=25%)
- Each panel: anonymous label (Model A), streaming area, vote button
- Synchronized scroll option
- Reveal button shows actual model names

## Responsive Design

| Breakpoint | Layout |
|------------|--------|
| Desktop (>1024px) | Sidebar + main content side by side |
| Tablet (768-1024px) | Collapsible sidebar overlay |
| Mobile (<768px) | Bottom nav, stacked views |

PWA support:
- `manifest.json` with icons
- Service worker for offline shell
- `theme-color` meta tag
- Standalone display mode
