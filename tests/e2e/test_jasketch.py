"""E2E tests for JaSketch drawing application.

Tests cover: UI rendering, tool selection, shape drawing, text editing,
shape text, undo/redo, delete, export, and zoom/pan.

Prerequisites:
    pip install playwright pytest-playwright pytest-timeout
    playwright install chromium --with-deps

Run:
    pytest tests/e2e/test_jasketch.py -v
    pytest tests/e2e/test_jasketch.py -v -k drawing
    pytest tests/e2e/test_jasketch.py -v --headed
"""

from playwright.sync_api import Page, expect

ACTION_DELAY = 300  # ms between UI actions


# -- Helpers -------------------------------------------------------------------


def get_canvas(page: Page):
    """Get the main drawing canvas element."""
    return page.locator("canvas").first


def select_tool(page: Page, tool_title: str):
    """Select a tool from the toolbar by its title prefix (e.g., 'Rectangle')."""
    page.locator(f"button[title^='{tool_title}']").click()
    page.wait_for_timeout(ACTION_DELAY)


def draw_shape(page: Page, tool: str, x1: int, y1: int, x2: int, y2: int):
    """Select a tool and draw by dragging from (x1,y1) to (x2,y2) on canvas.
    Coordinates are relative to the canvas element."""
    select_tool(page, tool)
    canvas = get_canvas(page)
    box = canvas.bounding_box()
    page.mouse.move(box["x"] + x1, box["y"] + y1)
    page.mouse.down()
    page.mouse.move(box["x"] + x2, box["y"] + y2, steps=10)
    page.mouse.up()
    page.wait_for_timeout(ACTION_DELAY)


def draw_line(page: Page, tool: str, x1: int, y1: int, x2: int, y2: int):
    """Draw a line/arrow from (x1,y1) to (x2,y2) on canvas."""
    select_tool(page, tool)
    canvas = get_canvas(page)
    box = canvas.bounding_box()
    page.mouse.move(box["x"] + x1, box["y"] + y1)
    page.mouse.down()
    page.mouse.move(box["x"] + x2, box["y"] + y2, steps=10)
    page.mouse.up()
    page.wait_for_timeout(ACTION_DELAY)


def click_canvas(page: Page, x: int, y: int):
    """Single click at position on canvas (uses force to bypass overlays)."""
    canvas = get_canvas(page)
    canvas.click(position={"x": x, "y": y}, force=True)
    page.wait_for_timeout(ACTION_DELAY)


def double_click_canvas(page: Page, x: int, y: int):
    """Double click at position on canvas (uses force to bypass overlays)."""
    canvas = get_canvas(page)
    canvas.dblclick(position={"x": x, "y": y}, force=True)
    page.wait_for_timeout(ACTION_DELAY)


def wait_for_elements(page: Page, expected_count: int, timeout: int = 5000):
    """Wait until localStorage has the expected number of elements."""
    page.wait_for_function(
        f"""() => {{
            const data = localStorage.getItem('jasketch_elements');
            if (!data) return {expected_count} === 0;
            return JSON.parse(data).length === {expected_count};
        }}""",
        timeout=timeout,
    )


def get_elements_count(page: Page) -> int:
    """Get the number of elements stored in the app."""
    return page.evaluate(
        """() => {
            const data = localStorage.getItem('jasketch_elements');
            if (!data) return 0;
            return JSON.parse(data).length;
        }"""
    )


def get_elements(page: Page) -> list:
    """Get all elements from localStorage."""
    return page.evaluate(
        """() => {
            const data = localStorage.getItem('jasketch_elements');
            if (!data) return [];
            return JSON.parse(data);
        }"""
    )


def clear_canvas(page: Page):
    """Clear all elements and verify canvas is empty."""
    # Click canvas first to ensure it has focus, away from sidebar
    canvas = get_canvas(page)
    canvas.click(position={"x": 500, "y": 300}, force=True)
    page.wait_for_timeout(200)
    page.keyboard.press("Escape")
    page.wait_for_timeout(100)
    page.keyboard.press("Control+a")
    page.wait_for_timeout(100)
    page.keyboard.press("Delete")
    page.wait_for_timeout(100)
    # Force-clear localStorage as a safety net
    page.evaluate("() => localStorage.setItem('jasketch_elements', '[]')")
    page.wait_for_timeout(ACTION_DELAY)
    # Verify canvas is actually empty
    wait_for_elements(page, 0, timeout=3000)


def press_key(page: Page, key: str):
    """Press a keyboard shortcut."""
    page.keyboard.press(key)
    page.wait_for_timeout(ACTION_DELAY)


# All draw coordinates use X >= 350 to avoid the sidebar (left-3, ~230px wide)
# and Y >= 50 to stay within the canvas area.
# Shapes are drawn in the center-right area of the canvas.

S_X1 = 400  # shape start X
S_Y1 = 100  # shape start Y
S_X2 = 600  # shape end X
S_Y2 = 250  # shape end Y
S_CX = 500  # shape center X (for clicking inside shape)
S_CY = 175  # shape center Y


# -- Rendering tests -----------------------------------------------------------


class TestRendering:
    """Verify the JaSketch UI loads correctly."""

    def test_canvas_visible(self, app: Page):
        """Canvas element is rendered and visible."""
        expect(get_canvas(app)).to_be_visible()

    def test_topbar_visible(self, app: Page):
        """Top toolbar with app name is visible."""
        expect(app.get_by_text("JaSketch")).to_be_visible()

    def test_toolbar_has_tools(self, app: Page):
        """All drawing tools are available in the toolbar."""
        tools = ["Select", "Pencil", "Line", "Arrow", "Rectangle", "Diamond", "Ellipse", "Text"]
        for tool in tools:
            expect(app.locator(f"button[title^='{tool}']")).to_be_visible()

    def test_zoom_controls_visible(self, app: Page):
        """Zoom controls are visible at bottom-left."""
        expect(app.get_by_text("100%")).to_be_visible()


# -- Tool selection tests ------------------------------------------------------


class TestToolSelection:
    """Verify tool switching works."""

    def test_select_rectangle_tool(self, app: Page):
        """Clicking Rectangle tool makes it the active tool."""
        select_tool(app, "Rectangle")
        btn = app.locator("button[title^='Rectangle']")
        expect(btn).to_be_visible()
        btn_class = btn.get_attribute("class")
        assert "text-orange-600" in btn_class, f"Rectangle should be active, class: {btn_class}"

    def test_select_tool_via_keyboard(self, app: Page):
        """Pressing number keys selects corresponding tools."""
        # Press '5' for rectangle — button should get active styling
        press_key(app, "5")
        rect_btn = app.locator("button[title^='Rectangle']")
        rect_class = rect_btn.get_attribute("class")
        assert "text-orange-600" in rect_class, f"Rectangle should be active, class: {rect_class}"
        # Press '1' to go back to select
        press_key(app, "1")
        select_btn = app.locator("button[title^='Select']")
        sel_class = select_btn.get_attribute("class")
        assert "text-orange-600" in sel_class, f"Select should be active, class: {sel_class}"

    def test_tool_switches_back_after_drawing(self, app: Page):
        """After drawing a shape, tool should switch back to select."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        # Tool should auto-switch to select — select button should be active
        select_btn = app.locator("button[title^='Select']")
        sel_class = select_btn.get_attribute("class")
        assert "text-orange-600" in sel_class, f"Select should be active after drawing, class: {sel_class}"


# -- Drawing tests -------------------------------------------------------------


class TestDrawing:
    """Verify shapes can be drawn on the canvas."""

    def test_draw_rectangle(self, app: Page):
        """Drawing a rectangle adds it to elements."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "rectangle"

    def test_draw_circle(self, app: Page):
        """Drawing a circle/ellipse adds it to elements."""
        clear_canvas(app)
        draw_shape(app, "Ellipse", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "circle"

    def test_draw_diamond(self, app: Page):
        """Drawing a diamond adds it to elements."""
        clear_canvas(app)
        draw_shape(app, "Diamond", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "diamond"

    def test_draw_line(self, app: Page):
        """Drawing a line adds it to elements."""
        clear_canvas(app)
        draw_line(app, "Line", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "line"

    def test_draw_arrow(self, app: Page):
        """Drawing an arrow adds it to elements."""
        clear_canvas(app)
        draw_line(app, "Arrow", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "arrow"

    def test_draw_freehand(self, app: Page):
        """Drawing freehand adds it to elements."""
        clear_canvas(app)
        select_tool(app, "Pencil")
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + S_X1, box["y"] + S_Y1)
        app.mouse.down()
        app.mouse.move(box["x"] + S_X1 + 50, box["y"] + S_Y1 + 30, steps=5)
        app.mouse.move(box["x"] + S_X1 + 100, box["y"] + S_Y1, steps=5)
        app.mouse.move(box["x"] + S_X1 + 150, box["y"] + S_Y1 + 50, steps=5)
        app.mouse.up()
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "freehand"

    def test_draw_multiple_shapes(self, app: Page):
        """Drawing multiple shapes accumulates elements with correct types."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 350, 80, 500, 160)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 520, 80, 670, 160)
        wait_for_elements(app, 2)
        draw_shape(app, "Diamond", 700, 80, 850, 160)
        wait_for_elements(app, 3)
        elements = get_elements(app)
        types = [e["type"] for e in elements]
        assert "rectangle" in types, f"Rectangle missing in {types}"
        assert "circle" in types, f"Circle missing in {types}"
        assert "diamond" in types, f"Diamond missing in {types}"


# -- Text tests ----------------------------------------------------------------


class TestText:
    """Verify text creation via text tool and double-click."""

    def test_create_text_element(self, app: Page):
        """Text tool creates a text element on canvas."""
        clear_canvas(app)
        select_tool(app, "Text")
        click_canvas(app, S_CX, S_CY)
        textarea = app.locator("textarea.canvas-text-input")
        expect(textarea).to_be_visible()
        textarea.focus()
        textarea.fill("Hello JaSketch")
        textarea.press("Escape")
        app.wait_for_timeout(ACTION_DELAY)
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "text"
        assert elements[0]["text"] == "Hello JaSketch"

    def test_double_click_creates_text(self, app: Page):
        """Double-clicking empty canvas creates text input."""
        clear_canvas(app)
        select_tool(app, "Select")
        double_click_canvas(app, S_CX, S_CY)
        textarea = app.locator("textarea.canvas-text-input")
        expect(textarea).to_be_visible()
        textarea.focus()
        textarea.fill("Double click text")
        textarea.press("Escape")
        app.wait_for_timeout(ACTION_DELAY)
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["text"] == "Double click text"


# -- Shape text tests ----------------------------------------------------------


class TestShapeText:
    """Verify double-click on shapes to add/edit text inside."""

    def test_add_text_to_rectangle(self, app: Page):
        """Double-clicking a rectangle opens text editor and saves shapeText."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        double_click_canvas(app, S_CX, S_CY)
        textarea = app.locator("textarea.canvas-text-input")
        expect(textarea).to_be_visible()
        textarea.focus()
        textarea.fill("Inside Rect")
        textarea.press("Escape")
        app.wait_for_timeout(ACTION_DELAY)
        elements = get_elements(app)
        assert elements[0]["type"] == "rectangle"
        assert elements[0].get("shapeText") == "Inside Rect"

    def test_edit_existing_shape_text(self, app: Page):
        """Double-clicking a shape with existing text opens editor with that text."""
        clear_canvas(app)
        draw_shape(app, "Ellipse", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        # Add text first
        double_click_canvas(app, S_CX, S_CY)
        textarea = app.locator("textarea.canvas-text-input")
        textarea.focus()
        textarea.fill("First text")
        textarea.press("Escape")
        app.wait_for_timeout(ACTION_DELAY)
        # Double-click again to edit
        double_click_canvas(app, S_CX, S_CY)
        textarea = app.locator("textarea.canvas-text-input")
        expect(textarea).to_be_visible()
        value = textarea.input_value()
        assert "First text" in value, f"Expected existing text, got: {value}"
        textarea.focus()
        textarea.fill("Updated text")
        textarea.press("Escape")
        app.wait_for_timeout(ACTION_DELAY)
        elements = get_elements(app)
        assert elements[0].get("shapeText") == "Updated text"


# -- Selection and deletion tests ----------------------------------------------


class TestSelectionAndDeletion:
    """Verify element selection and deletion."""

    def test_select_element_by_click(self, app: Page):
        """Clicking on an element selects it."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        expect(app.get_by_text("rectangle selected")).to_be_visible(timeout=5_000)

    def test_delete_selected_element(self, app: Page):
        """Pressing Delete removes the selected element."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        app.wait_for_timeout(ACTION_DELAY)
        press_key(app, "Delete")
        wait_for_elements(app, 0)

    def test_select_all(self, app: Page):
        """Ctrl+A selects all elements."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 350, 80, 500, 160)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 550, 80, 700, 160)
        wait_for_elements(app, 2)
        select_tool(app, "Select")
        press_key(app, "Control+a")
        press_key(app, "Delete")
        wait_for_elements(app, 0)


# -- Undo/Redo tests ----------------------------------------------------------


class TestUndoRedo:
    """Verify undo and redo functionality."""

    def test_undo_removes_last_element(self, app: Page):
        """Ctrl+Z undoes the last action."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        press_key(app, "Control+z")
        wait_for_elements(app, 0)

    def test_redo_restores_element(self, app: Page):
        """Ctrl+Y redoes the undone action."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        press_key(app, "Control+z")
        wait_for_elements(app, 0)
        press_key(app, "Control+y")
        wait_for_elements(app, 1)


# -- Context menu tests --------------------------------------------------------


class TestContextMenu:
    """Verify right-click context menu operations."""

    def test_context_menu_appears(self, app: Page):
        """Right-clicking on an element shows context menu."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        canvas = get_canvas(app)
        canvas.click(position={"x": S_CX, "y": S_CY}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        expect(app.get_by_text("Duplicate")).to_be_visible()
        expect(app.get_by_text("Delete")).to_be_visible()
        expect(app.get_by_text("Export as PNG")).to_be_visible()
        expect(app.get_by_text("Copy as PNG")).to_be_visible()
        press_key(app, "Escape")

    def test_duplicate_from_menu(self, app: Page):
        """Duplicating via Ctrl+D creates a copy with same type."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        press_key(app, "Control+d")
        wait_for_elements(app, 2)
        elements = get_elements(app)
        assert elements[0]["type"] == "rectangle", "Original should be rectangle"
        assert elements[1]["type"] == "rectangle", "Duplicate should also be rectangle"


# -- Zoom tests ----------------------------------------------------------------


class TestZoom:
    """Verify zoom controls work."""

    def test_zoom_in_button(self, app: Page):
        """Clicking + zoom button increases zoom above 100%."""
        clear_canvas(app)
        press_key(app, "Control+0")  # Reset to 100% first
        zoom_buttons = app.locator("button", has_text="+")
        zoom_buttons.last.click()
        app.wait_for_timeout(ACTION_DELAY)
        # Zoom should now be above 100% (e.g., 110%)
        zoom_btn = app.locator("button", has_text="%")
        zoom_label = zoom_btn.text_content()
        zoom_val = int(zoom_label.replace("%", ""))
        assert zoom_val > 100, f"Zoom should be above 100% after zoom in, got {zoom_val}%"

    def test_zoom_reset(self, app: Page):
        """Ctrl+0 resets zoom to 100%."""
        press_key(app, "Control+0")
        app.wait_for_timeout(ACTION_DELAY)
        expect(app.get_by_text("100%")).to_be_visible()


# -- Persistence tests ---------------------------------------------------------


class TestPersistence:
    """Verify elements persist across page reloads."""

    def test_elements_persist_after_reload(self, app: Page):
        """Elements are saved to localStorage and restored on reload."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 650, 100, 800, 200)
        wait_for_elements(app, 2)
        app.reload(wait_until="load")
        app.locator("canvas").first.wait_for(state="visible", timeout=30_000)
        app.wait_for_timeout(1000)
        count = get_elements_count(app)
        assert count == 2, f"Expected 2 elements after reload, got {count}"

    def test_element_types_preserved(self, app: Page):
        """Element types are correctly preserved after reload."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        draw_shape(app, "Diamond", 650, 100, 800, 200)
        wait_for_elements(app, 2)
        app.reload(wait_until="load")
        app.locator("canvas").first.wait_for(state="visible", timeout=30_000)
        app.wait_for_timeout(1000)
        elements = get_elements(app)
        types = [e["type"] for e in elements]
        assert "rectangle" in types, f"Rectangle not found in {types}"
        assert "diamond" in types, f"Diamond not found in {types}"


# -- Moving tests --------------------------------------------------------------


class TestMoving:
    """Verify element dragging/moving."""

    def test_single_element_move(self, app: Page):
        """Dragging a selected element changes its position."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        old_elements = get_elements(app)
        old_x = old_elements[0]["x"]
        old_y = old_elements[0]["y"]
        # Select and drag the shape
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + S_CX, box["y"] + S_CY)
        app.mouse.down()
        app.mouse.move(box["x"] + S_CX + 80, box["y"] + S_CY + 60, steps=10)
        app.mouse.up()
        app.wait_for_timeout(ACTION_DELAY)
        new_elements = get_elements(app)
        new_x = new_elements[0]["x"]
        new_y = new_elements[0]["y"]
        assert abs(new_x - old_x - 80) < 10, f"Expected X to move ~80px, moved {new_x - old_x}"
        assert abs(new_y - old_y - 60) < 10, f"Expected Y to move ~60px, moved {new_y - old_y}"

    def test_multi_select_move(self, app: Page):
        """Moving multiple selected elements moves all of them."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 400, 80, 500, 150)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 600, 80, 700, 150)
        wait_for_elements(app, 2)
        old_elements = get_elements(app)
        old_x0 = old_elements[0]["x"]
        old_x1 = old_elements[1]["x"]
        # Select all and drag
        select_tool(app, "Select")
        press_key(app, "Control+a")
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + 450, box["y"] + 115)
        app.mouse.down()
        app.mouse.move(box["x"] + 450 + 50, box["y"] + 115 + 50, steps=10)
        app.mouse.up()
        app.wait_for_timeout(ACTION_DELAY)
        new_elements = get_elements(app)
        # Both shapes should have moved by same delta
        delta_x0 = new_elements[0]["x"] - old_x0
        delta_x1 = new_elements[1]["x"] - old_x1
        assert abs(delta_x0 - 50) < 10, f"Element 0 X delta should be ~50, got {delta_x0}"
        assert abs(delta_x1 - 50) < 10, f"Element 1 X delta should be ~50, got {delta_x1}"


# -- Connected shapes tests ----------------------------------------------------


class TestConnectedShapes:
    """Verify arrow/line connections follow when shapes are moved."""

    def test_arrow_follows_shape_move(self, app: Page):
        """Moving a shape updates the connected arrow endpoint."""
        clear_canvas(app)
        # Draw two shapes
        draw_shape(app, "Rectangle", 350, 80, 480, 160)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 600, 200, 750, 300)
        wait_for_elements(app, 2)
        # Draw arrow from bottom of rectangle to top of ellipse
        # The connection points are at shape edges; arrow snaps to nearest
        draw_line(app, "Arrow", 415, 160, 675, 200)
        wait_for_elements(app, 3)
        old_elements = get_elements(app)
        arrow = old_elements[2]
        old_arrow_x1 = arrow["x1"]
        old_arrow_y1 = arrow["y1"]
        # Move the rectangle (element 0) down
        select_tool(app, "Select")
        click_canvas(app, 415, 120)
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + 415, box["y"] + 120)
        app.mouse.down()
        app.mouse.move(box["x"] + 415, box["y"] + 180, steps=10)
        app.mouse.up()
        app.wait_for_timeout(500)
        new_elements = get_elements(app)
        new_arrow = new_elements[2]
        # Arrow start point should have moved with the rectangle
        moved_y = new_arrow["y1"] - old_arrow_y1
        assert abs(moved_y - 60) < 20, f"Arrow y1 should follow rectangle move (~60px), got {moved_y}"


# -- Copy/Paste tests ----------------------------------------------------------


class TestCopyPaste:
    """Verify element copy and paste operations."""

    def test_copy_paste_element(self, app: Page):
        """Ctrl+C then Ctrl+V duplicates the selected element."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        press_key(app, "Control+c")
        press_key(app, "Control+v")
        wait_for_elements(app, 2)
        elements = get_elements(app)
        assert elements[0]["type"] == "rectangle"
        assert elements[1]["type"] == "rectangle"

    def test_copy_paste_preserves_type(self, app: Page):
        """Pasted element has the same type as the original."""
        clear_canvas(app)
        draw_shape(app, "Diamond", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        press_key(app, "Control+c")
        press_key(app, "Control+v")
        wait_for_elements(app, 2)
        elements = get_elements(app)
        assert elements[1]["type"] == "diamond"

    def test_duplicate_shortcut(self, app: Page):
        """Ctrl+D duplicates the selected element with same type."""
        clear_canvas(app)
        draw_shape(app, "Ellipse", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        press_key(app, "Control+d")
        wait_for_elements(app, 2)
        elements = get_elements(app)
        assert elements[0]["type"] == "circle", "Original should be circle"
        assert elements[1]["type"] == "circle", "Duplicate should also be circle"

    def test_copy_paste_independent_ids(self, app: Page):
        """Copied/pasted elements have independent IDs; deleting one doesn't delete both."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        press_key(app, "Control+c")
        press_key(app, "Control+v")
        wait_for_elements(app, 2)
        elements = get_elements(app)
        # Verify two separate IDs
        assert elements[0]["id"] != elements[1]["id"], "Pasted element must have unique ID"
        # Select and delete the pasted (second) element
        click_canvas(app, S_CX + 30, S_CY + 30)  # Click on the offset copy
        press_key(app, "Delete")
        wait_for_elements(app, 1)
        remaining = get_elements(app)
        assert remaining[0]["id"] == elements[0]["id"], "Original should remain after deleting copy"

    def test_duplicate_independent_ids(self, app: Page):
        """Duplicated elements have independent IDs; deleting one doesn't delete the other."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        press_key(app, "Control+d")
        wait_for_elements(app, 2)
        elements = get_elements(app)
        # Verify two separate IDs
        assert elements[0]["id"] != elements[1]["id"], "Duplicated element must have unique ID"
        # Select and delete the duplicate (second) element
        click_canvas(app, S_CX + 30, S_CY + 30)
        press_key(app, "Delete")
        wait_for_elements(app, 1)
        remaining = get_elements(app)
        assert remaining[0]["id"] == elements[0]["id"], "Original should remain after deleting duplicate"

    def test_cut_removes_element(self, app: Page):
        """Ctrl+X cuts the element (removes it and copies to clipboard for pasting)."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        press_key(app, "Control+x")
        wait_for_elements(app, 0)
        # Verify pasting restores the element
        press_key(app, "Control+v")
        wait_for_elements(app, 1)
        elements = get_elements(app)
        assert elements[0]["type"] == "rectangle"

    def test_reset_canvas_clears_all(self, app: Page):
        """Ctrl+Delete opens confirmation dialog; clicking Reset clears all elements."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        draw_shape(app, "Diamond", S_X1 + 100, S_Y1 + 100, S_X2 + 100, S_Y2 + 100)
        wait_for_elements(app, 2)
        # Press Ctrl+Delete to open confirmation dialog
        press_key(app, "Control+Delete")
        app.wait_for_timeout(300)  # Wait for dialog animation
        # Click the "Reset" button (right button in the dialog)
        buttons = app.query_selector_all("button")
        reset_button = None
        for btn in buttons:
            if "Reset" in btn.text_content():
                reset_button = btn
                break
        assert reset_button is not None, "Reset button not found"
        reset_button.click()
        wait_for_elements(app, 0)


# -- Grouping tests ------------------------------------------------------------


class TestGrouping:
    """Verify element grouping and group operations."""

    def test_group_elements(self, app: Page):
        """Group selected elements via context menu."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 400, 80, 550, 150)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 600, 80, 750, 150)
        wait_for_elements(app, 2)
        select_tool(app, "Select")
        # Box-select both shapes
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + 380, box["y"] + 60)
        app.mouse.down()
        app.mouse.move(box["x"] + 770, box["y"] + 170, steps=10)
        app.mouse.up()
        app.wait_for_timeout(500)
        # Use context menu to group (avoids stale closure issue with Ctrl+G)
        canvas.click(position={"x": 450, "y": 115}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        group_btn = app.locator("button", has_text="Group")
        group_btn.click()
        app.wait_for_timeout(1000)
        elements = get_elements(app)
        assert elements[0].get("groupId") is not None, "Element 0 should have groupId"
        assert elements[1].get("groupId") is not None, "Element 1 should have groupId"
        assert elements[0]["groupId"] == elements[1]["groupId"], "Both should share same groupId"

    def test_ungroup_elements(self, app: Page):
        """Ungroup elements via context menu."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 400, 80, 550, 150)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 600, 80, 750, 150)
        wait_for_elements(app, 2)
        select_tool(app, "Select")
        # Box-select both shapes
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + 380, box["y"] + 60)
        app.mouse.down()
        app.mouse.move(box["x"] + 770, box["y"] + 170, steps=10)
        app.mouse.up()
        app.wait_for_timeout(500)
        # Group via context menu
        canvas.click(position={"x": 450, "y": 115}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        app.locator("button", has_text="Group").click()
        app.wait_for_timeout(1000)
        # Verify grouped
        elements = get_elements(app)
        assert elements[0].get("groupId") is not None, "Should be grouped first"
        # Click on a grouped element to select the group
        click_canvas(app, 450, 115)
        app.wait_for_timeout(ACTION_DELAY)
        # Ungroup via context menu
        canvas.click(position={"x": 450, "y": 115}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        ungroup_btn = app.locator("button", has_text="Ungroup")
        expect(ungroup_btn).to_be_visible(timeout=3_000)
        ungroup_btn.click()
        app.wait_for_timeout(1000)
        elements = get_elements(app)
        gid0 = elements[0].get("groupId")
        assert gid0 is None or gid0 == "", f"Element 0 groupId should be cleared, got {gid0}"

    def test_move_grouped_elements(self, app: Page):
        """Moving one element in a group moves all group members."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 400, 80, 550, 150)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 600, 80, 750, 150)
        wait_for_elements(app, 2)
        select_tool(app, "Select")
        # Box-select and group via context menu
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + 380, box["y"] + 60)
        app.mouse.down()
        app.mouse.move(box["x"] + 770, box["y"] + 170, steps=10)
        app.mouse.up()
        app.wait_for_timeout(500)
        canvas.click(position={"x": 450, "y": 115}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        app.locator("button", has_text="Group").click()
        app.wait_for_timeout(1000)
        press_key(app, "Control+g")
        app.wait_for_timeout(500)
        old_elements = get_elements(app)
        old_x0 = old_elements[0]["x"]
        old_x1 = old_elements[1]["x"]
        # Click on first element (should select whole group)
        click_canvas(app, 450, 115)
        canvas = get_canvas(app)
        box = canvas.bounding_box()
        app.mouse.move(box["x"] + 450, box["y"] + 115)
        app.mouse.down()
        app.mouse.move(box["x"] + 450 + 40, box["y"] + 115 + 40, steps=10)
        app.mouse.up()
        app.wait_for_timeout(ACTION_DELAY)
        new_elements = get_elements(app)
        delta0 = new_elements[0]["x"] - old_x0
        delta1 = new_elements[1]["x"] - old_x1
        assert abs(delta0 - 40) < 10, f"Group element 0 should move ~40px, got {delta0}"
        assert abs(delta1 - 40) < 10, f"Group element 1 should move ~40px, got {delta1}"


# -- Color change tests --------------------------------------------------------


class TestColorChange:
    """Verify element color changes from sidebar."""

    def test_change_stroke_color(self, app: Page):
        """Changing stroke color updates the selected element."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        # Sidebar should show stroke colors — click a red color (#e03131)
        color_btn = app.locator("button[title='#e03131']").first
        expect(color_btn).to_be_visible(timeout=3_000)
        color_btn.click()
        app.wait_for_timeout(ACTION_DELAY)
        elements = get_elements(app)
        assert elements[0]["color"] == "#e03131", f"Expected red color, got {elements[0]['color']}"

    def test_change_fill_color(self, app: Page):
        """Changing fill color updates the selected shape."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        # Click "Fill with stroke color" button
        fill_btn = app.locator("button[title='Fill with stroke color']")
        expect(fill_btn).to_be_visible(timeout=3_000)
        fill_btn.click()
        app.wait_for_timeout(ACTION_DELAY)
        elements = get_elements(app)
        assert elements[0]["fillColor"] != "transparent", f"Expected fill color, got {elements[0]['fillColor']}"


# -- Canvas panning tests ------------------------------------------------------


class TestPanning:
    """Verify canvas panning (scroll to pan)."""

    def test_vertical_pan(self, app: Page):
        """Scrolling vertically pans the canvas (element stays, viewport moves)."""
        clear_canvas(app)
        # Reset zoom first
        press_key(app, "Control+0")
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        old_elements = get_elements(app)
        old_y = old_elements[0]["y"]
        # Scroll down on canvas — this pans the viewport, not the element
        canvas = get_canvas(app)
        canvas.hover(position={"x": S_CX, "y": S_CY})
        app.mouse.wheel(0, 200)
        app.wait_for_timeout(ACTION_DELAY)
        # Element world coords should NOT change (only viewport moves)
        new_elements = get_elements(app)
        assert new_elements[0]["y"] == old_y, f"Element Y should stay at {old_y}, got {new_elements[0]['y']}"
        # Zoom button should still read 100% (we didn't Ctrl+scroll)
        zoom_btn = app.locator("button", has_text="100%")
        expect(zoom_btn).to_be_visible()

    def test_horizontal_pan(self, app: Page):
        """Shift+scroll pans horizontally (element stays, viewport moves)."""
        clear_canvas(app)
        press_key(app, "Control+0")
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        old_elements = get_elements(app)
        old_x = old_elements[0]["x"]
        # Shift+scroll = horizontal pan
        canvas = get_canvas(app)
        canvas.hover(position={"x": S_CX, "y": S_CY})
        app.keyboard.down("Shift")
        app.mouse.wheel(200, 0)
        app.keyboard.up("Shift")
        app.wait_for_timeout(ACTION_DELAY)
        # Element world coords should NOT change
        new_elements = get_elements(app)
        assert new_elements[0]["x"] == old_x, f"Element X should stay at {old_x}, got {new_elements[0]['x']}"


# -- Export tests --------------------------------------------------------------


class TestExport:
    """Verify export functionality."""

    def test_export_png_triggers_download(self, app: Page):
        """Export as PNG triggers a file download."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        # Right-click to open context menu
        canvas = get_canvas(app)
        canvas.click(position={"x": S_CX, "y": S_CY}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        # Click Export as PNG and expect download
        with app.expect_download(timeout=10_000) as download_info:
            app.get_by_text("Export as PNG", exact=True).click()
        download = download_info.value
        assert download.suggested_filename.endswith(".png"), f"Expected .png download, got {download.suggested_filename}"

    def test_export_svg_triggers_download(self, app: Page):
        """Export as SVG triggers a file download."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        # Right-click to open context menu
        canvas = get_canvas(app)
        canvas.click(position={"x": S_CX, "y": S_CY}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        # Click Export as SVG and expect download
        with app.expect_download(timeout=10_000) as download_info:
            app.get_by_text("Export as SVG", exact=True).click()
        download = download_info.value
        assert download.suggested_filename.endswith(".svg"), f"Expected .svg download, got {download.suggested_filename}"

    def test_copy_as_png_shows_toast(self, app: Page):
        """Copy as PNG shows confirmation toast."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        select_tool(app, "Select")
        click_canvas(app, S_CX, S_CY)
        canvas = get_canvas(app)
        canvas.click(position={"x": S_CX, "y": S_CY}, button="right", force=True)
        app.wait_for_timeout(ACTION_DELAY)
        app.get_by_text("Copy as PNG", exact=True).click()
        # Toast should appear
        expect(app.get_by_text("Copied as PNG")).to_be_visible(timeout=5_000)


# -- Image tests ---------------------------------------------------------------


class TestImage:
    """Verify image element handling."""

    def test_image_element_persists(self, app: Page):
        """Image elements persist correctly (src as data URL in localStorage)."""
        clear_canvas(app)
        # Inject an image element directly via localStorage (simulates paste)
        app.evaluate(
            """() => {
                const el = {
                    type: 'image',
                    x: 400, y: 100,
                    width: 100, height: 80,
                    src: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
                    opacity: 1.0
                };
                localStorage.setItem('jasketch_elements', JSON.stringify([el]));
            }"""
        )
        app.reload(wait_until="load")
        app.locator("canvas").first.wait_for(state="visible", timeout=30_000)
        app.wait_for_timeout(1000)
        elements = get_elements(app)
        assert len(elements) == 1, f"Expected 1 element, got {len(elements)}"
        assert elements[0]["type"] == "image"
        assert elements[0]["src"].startswith("data:image/"), "Image src should be a data URL"

    def test_image_no_imageobj_in_storage(self, app: Page):
        """imageObj should not be stored in localStorage (non-serializable)."""
        clear_canvas(app)
        # Inject image and reload
        app.evaluate(
            """() => {
                const el = {
                    type: 'image',
                    x: 400, y: 100,
                    width: 100, height: 80,
                    src: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
                    opacity: 1.0
                };
                localStorage.setItem('jasketch_elements', JSON.stringify([el]));
            }"""
        )
        app.reload(wait_until="load")
        app.locator("canvas").first.wait_for(state="visible", timeout=30_000)
        app.wait_for_timeout(1000)
        # After app loads and potentially adds imageObj, check localStorage
        raw = app.evaluate("() => localStorage.getItem('jasketch_elements')")
        assert "imageObj" not in raw, "imageObj should not be in localStorage"

    def test_paste_image_from_clipboard(self, app: Page):
        """Pasting an image from the system clipboard creates an image element."""
        clear_canvas(app)
        # Write a small PNG to the clipboard via the browser API
        app.evaluate(
            """async () => {
                // 1x1 red PNG as base64
                const b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
                const bin = atob(b64);
                const arr = new Uint8Array(bin.length);
                for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
                const blob = new Blob([arr], {type: 'image/png'});
                const item = new ClipboardItem({'image/png': blob});
                await navigator.clipboard.write([item]);
            }"""
        )
        app.wait_for_timeout(ACTION_DELAY)
        # Focus the canvas and paste
        click_canvas(app, 500, 300)
        press_key(app, "Control+v")
        # Wait for the async clipboard read + image load + element creation
        wait_for_elements(app, 1, timeout=10_000)
        elements = get_elements(app)
        assert len(elements) == 1, f"Expected 1 image element, got {len(elements)}"
        assert elements[0]["type"] == "image", f"Expected image type, got {elements[0]['type']}"
        assert elements[0]["src"].startswith("data:image/"), "Image src should be a data URL"


# -- Select all tests ----------------------------------------------------------


class TestSelectAll:
    """Verify select all functionality."""

    def test_select_all_elements(self, app: Page):
        """Ctrl+A selects all elements on canvas."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 400, 80, 500, 150)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 550, 80, 650, 150)
        wait_for_elements(app, 2)
        draw_shape(app, "Diamond", 700, 80, 800, 150)
        wait_for_elements(app, 3)
        select_tool(app, "Select")
        press_key(app, "Control+a")
        # Delete all — if all were selected, count should be 0
        press_key(app, "Delete")
        wait_for_elements(app, 0)

    def test_select_all_then_copy_paste(self, app: Page):
        """Select all then Ctrl+C + Ctrl+V duplicates all elements."""
        clear_canvas(app)
        draw_shape(app, "Rectangle", 400, 80, 500, 150)
        wait_for_elements(app, 1)
        draw_shape(app, "Ellipse", 550, 80, 650, 150)
        wait_for_elements(app, 2)
        select_tool(app, "Select")
        press_key(app, "Control+a")
        press_key(app, "Control+c")
        press_key(app, "Control+v")
        wait_for_elements(app, 4)
        elements = get_elements(app)
        types = [e["type"] for e in elements]
        assert types.count("rectangle") == 2, f"Expected 2 rectangles, got {types}"
        assert types.count("circle") == 2, f"Expected 2 circles, got {types}"


# -- Keyboard Shortcuts Help Popup tests ---------------------------------------


class TestShortcutHelp:
    """Verify keyboard shortcuts help popup functionality."""

    def test_shortcut_help_opens_on_question_mark(self, app: Page):
        """Pressing ? opens the shortcut help modal."""
        app.keyboard.press("?")
        app.wait_for_timeout(300)  # Wait for modal animation
        # Check for the ShortcutHelp modal presence by looking for the help title
        help_title = app.query_selector("text='Keyboard Shortcuts'")
        assert help_title is not None, "Keyboard Shortcuts help modal should be visible"

    def test_shortcut_help_closes_on_escape(self, app: Page):
        """Pressing Escape closes the shortcut help modal."""
        app.keyboard.press("?")
        app.wait_for_timeout(300)
        help_title = app.query_selector("text='Keyboard Shortcuts'")
        assert help_title is not None, "Help modal should be open"
        app.keyboard.press("Escape")
        app.wait_for_timeout(300)
        help_title_after = app.query_selector("text='Keyboard Shortcuts'")
        assert help_title_after is None, "Help modal should be closed after Escape"
