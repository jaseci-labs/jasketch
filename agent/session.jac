"""Session context node — holds conversation history and diagram blueprint per session."""

node SessionContext {
    has session_id: str = "";
    has conversation_log: str = "";
    has canvas_summary: str = "unknown";
    has diagram_blueprint: str = "";
    has turn_count: int = 0;

    """Append a conversation turn to context, compacting when over 3000 chars."""
    def append_turn(role: str, content: str) -> None {
        # Take first 200 chars of content to keep entries concise
        short_content: str = content[:200] if len(content) > 200 else content;
        line: str = f"[{role}] {short_content}\n";
        self.conversation_log = self.conversation_log + line;

        # Compact context when it exceeds 3000 chars
        if len(self.conversation_log) > 3000 {
            # Keep last ~2000 chars (deterministic, no LLM cost)
            self.conversation_log = self.conversation_log[-2000:];
        }

        self.turn_count += 1;
    }

    """Clear the diagram blueprint after rendering."""
    def clear_diagram_blueprint() -> None {
        self.diagram_blueprint = "";
    }
}
sem SessionContext = "Per-session ephemeral state: conversation history, canvas status, and diagram blueprint";
sem SessionContext.session_id = "Unique identifier for this chat session";
sem SessionContext.conversation_log = "Rolling transcript of recent turns, auto-compacted to ~2000 chars when it exceeds 3000";
sem SessionContext.canvas_summary = "Cached hint about canvas state for the router: 'empty', 'non-empty', or 'unknown' (may be stale)";
sem SessionContext.diagram_blueprint = "JSON-serialized BlueprintSpec from DiagramPlanner; empty string when no blueprint exists";
sem SessionContext.turn_count = "Total number of turns processed in this session";
