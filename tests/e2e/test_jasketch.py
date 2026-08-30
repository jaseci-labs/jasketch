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

import math
import re

import pytest
from playwright.sync_api import Page, expect

ACTION_DELAY = 300  # ms between UI actions
APP_READY_TIMEOUT = 60_000  # ms for a freshly opened page to render its canvas


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
        # The inspector names what you are editing. It reads "Rectangle" with a
        # "selected" state beside it, rather than one run-on phrase.
        # The DOM text is the raw type ("rectangle"); the capital is CSS.
        inspector = app.locator(".sidebar")
        expect(inspector.get_by_text(re.compile(r"^rectangle$", re.I))).to_be_visible(timeout=5_000)
        expect(inspector.get_by_text("selected", exact=True)).to_be_visible(timeout=5_000)

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


# -- Share link tests ----------------------------------------------------------


class TestShareLink:
    """The share round-trip: encrypt in the browser, store ciphertext server-side,
    reopen the link in a fresh tab and get the same scene back.

    Exercises services/sharing.jac (the def:pub endpoints + the SharedScene store
    on root.shared) through the real UI, so a broken RPC contract or a lost blob
    fails here rather than in production."""

    def test_share_link_round_trips_the_scene(self, app: Page, base_url):
        clear_canvas(app)
        draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
        wait_for_elements(app, 1)
        original = get_elements(app)

        app.locator("button[title^='Shareable link']").click()
        app.wait_for_timeout(ACTION_DELAY)
        app.get_by_text("Generate Link", exact=True).click()

        link_box = app.locator("input[readonly]").first
        expect(link_box).to_have_value(re.compile(r"#json="), timeout=20_000)
        share_url = link_box.input_value()
        assert "#json=" in share_url, share_url

        # A fresh context: no localStorage, so anything that renders must have
        # come back from the server.
        viewer = app.context.browser.new_context()
        try:
            page = viewer.new_page()
            page.goto(share_url, wait_until="load")
            page.locator("canvas").first.wait_for(state="visible", timeout=APP_READY_TIMEOUT)
            page.wait_for_function(
                """() => {
                    const d = localStorage.getItem('jasketch_elements');
                    return d && JSON.parse(d).length > 0;
                }""",
                timeout=20_000,
            )
            restored = page.evaluate(
                "() => JSON.parse(localStorage.getItem('jasketch_elements'))"
            )
            assert len(restored) == len(original)
            assert restored[0]["type"] == original[0]["type"]
        finally:
            viewer.close()
            # The `app` page is module-scoped: leave the modal closed or the next
            # test's toolbar clicks land on this backdrop.
            app.locator("div.fixed.inset-0 button", has_text="×").last.click()
            app.wait_for_timeout(ACTION_DELAY)

    def test_unknown_share_id_reports_an_error(self, app: Page, base_url):
        viewer = app.context.browser.new_context()
        try:
            page = viewer.new_page()
            page.goto(f"{base_url}/#json=doesnotexist,badkey", wait_until="load")
            page.locator("canvas").first.wait_for(state="visible", timeout=APP_READY_TIMEOUT)
            expect(page.get_by_text("Share not found or expired")).to_be_visible(
                timeout=20_000
            )
        finally:
            viewer.close()


# -- Live collaboration tests --------------------------------------------------


class TestLiveCollaboration:
    """Two tabs in one room, over the broadcast relay endpoint.

    Covers the whole collaboration path: a real per-room AES key, the encrypted
    room_broadcast, infrastructure/relay.jac's fan-out, and the client-side
    filter that decides which broadcast envelopes belong to this tab."""

    def test_scene_reaches_the_other_tab(self, app: Page, base_url):
        clear_canvas(app)

        app.locator("button[title^='Live Collaboration']").click()
        app.wait_for_timeout(ACTION_DELAY)
        app.get_by_text("Start Session", exact=True).click()

        link_box = app.locator("input[readonly]").first
        expect(link_box).to_have_value(re.compile(r"#room="), timeout=20_000)
        room_url = link_box.input_value()
        # room_key must be an independent secret, not a copy of room_id
        room_id, room_key = room_url.split("#room=")[1].split(",")
        assert room_key != room_id, "room_key is still a copy of room_id"

        # Scope the close to the dialog: an unscoped text match resolves behind
        # the modal backdrop and the click is intercepted.
        app.locator("div.fixed.inset-0 button", has_text="×").last.click()
        app.wait_for_timeout(ACTION_DELAY)

        guest_ctx = app.context.browser.new_context()
        try:
            guest = guest_ctx.new_page()
            guest.goto(room_url, wait_until="load")
            guest.locator("canvas").first.wait_for(state="visible", timeout=APP_READY_TIMEOUT)
            # The joiner is asked for a display name before the room activates.
            name_field = guest.locator("input[type='text']").first
            name_field.fill("Guest")
            guest.keyboard.press("Enter")
            guest.wait_for_timeout(2000)

            draw_shape(app, "Rectangle", S_X1, S_Y1, S_X2, S_Y2)
            wait_for_elements(app, 1)

            guest.wait_for_function(
                """() => {
                    const d = localStorage.getItem('jasketch_elements');
                    return d && JSON.parse(d).length > 0;
                }""",
                timeout=25_000,
            )
            mirrored = guest.evaluate(
                "() => JSON.parse(localStorage.getItem('jasketch_elements'))"
            )
            assert mirrored[0]["type"] == "rectangle"
        finally:
            guest_ctx.close()


# -- UX parity tests -----------------------------------------------------------
#
# These cover the interaction habits a user brings from Excalidraw. Each one
# stands for a gesture that silently did nothing before: they are here so a
# refactor cannot quietly take the muscle memory away again.


def drag_canvas(page: Page, x1: int, y1: int, x2: int, y2: int, modifier: str = ""):
    """Drag on the canvas, optionally holding a modifier for the whole gesture."""
    box = get_canvas(page).bounding_box()
    page.mouse.move(box["x"] + x1, box["y"] + y1)
    page.mouse.down()
    if modifier:
        page.keyboard.down(modifier)
    page.mouse.move(box["x"] + x2, box["y"] + y2, steps=10)
    page.mouse.up()
    if modifier:
        page.keyboard.up(modifier)
    page.wait_for_timeout(ACTION_DELAY)


class TestDigitShortcuts:
    """Tools answer to their toolbar digit. JaSketch uses digits only, on
    purpose: letter mnemonics were tried and deliberately pulled back out."""

    @pytest.mark.parametrize(
        "key,tool_title",
        [
            ("1", "Select"),
            ("2", "Pencil"),
            ("3", "Line"),
            ("4", "Arrow"),
            ("5", "Rectangle"),
            ("6", "Diamond"),
            ("7", "Ellipse"),
            ("8", "Text"),
        ],
    )
    def test_digit_selects_tool(self, app: Page, key: str, tool_title: str):
        press_key(app, "Escape")
        press_key(app, key)
        btn_class = app.locator(f"button[title^='{tool_title}']").get_attribute("class")
        assert "text-orange-600" in btn_class, (
            f"'{key}' should select {tool_title}, class: {btn_class}"
        )

    @pytest.mark.parametrize("letter", ["r", "d", "o", "a", "l", "p", "t", "v"])
    def test_letters_are_not_bound(self, app: Page, letter: str):
        """The digits-only decision is deliberate, so it is pinned. If a letter
        ever starts selecting a tool again it should be a choice, not a drift."""
        press_key(app, "Escape")
        press_key(app, "5")  # park on Rectangle
        press_key(app, letter)
        rect_class = app.locator("button[title^='Rectangle']").get_attribute("class")
        assert "text-orange-600" in rect_class, (
            f"'{letter}' should not change the tool, class: {rect_class}"
        )


class TestShiftConstrain:
    """Shift means 'keep it regular' both while drawing and while resizing."""

    def test_shift_draws_a_square(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 150, 640, 250, modifier="Shift")
        wait_for_elements(app, 1)
        el = get_elements(app)[0]
        assert abs(abs(el["width"]) - abs(el["height"])) < 3, (
            f"Shift should force a square, got {el['width']}x{el['height']}"
        )

    def test_no_shift_draws_a_free_rectangle(self, app: Page):
        """The constraint must be opt-in, or every rectangle becomes a square."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 150, 640, 250)
        wait_for_elements(app, 1)
        el = get_elements(app)[0]
        assert abs(abs(el["width"]) - abs(el["height"])) > 50, (
            f"Without Shift the drag should stay free, got {el['width']}x{el['height']}"
        )

    def test_shift_snaps_a_line_to_45_degrees(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "3")
        # A 240x100 drag is ~23 degrees; Shift should pull it to a flat 0.
        drag_canvas(app, 400, 200, 640, 300, modifier="Shift")
        wait_for_elements(app, 1)
        el = get_elements(app)[0]
        angle = math.degrees(math.atan2(el["y2"] - el["y1"], el["x2"] - el["x1"]))
        nearest = round(angle / 45.0) * 45.0
        assert abs(angle - nearest) < 3, f"Line should snap to a 45 multiple, got {angle:.1f}deg"

    def test_shift_corner_resize_keeps_aspect_ratio(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 150, 560, 230)  # 160x80, a 2:1 box
        wait_for_elements(app, 1)
        click_canvas(app, 480, 190)  # select it
        drag_canvas(app, 560, 230, 700, 280, modifier="Shift")  # drag the SE handle
        el = get_elements(app)[0]
        ratio = abs(el["width"]) / max(abs(el["height"]), 1)
        assert abs(ratio - 2.0) < 0.15, f"Shift should hold the 2:1 ratio, got {ratio:.2f}"


class TestToolLock:
    """Q keeps a tool armed so a diagram can be drawn without re-picking."""

    def test_lock_keeps_the_tool_after_each_shape(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        press_key(app, "q")
        try:
            for x in (350, 500, 650):
                drag_canvas(app, x, 300, x + 90, 380)
            wait_for_elements(app, 3)
            assert get_elements_count(app) == 3, "A locked tool should draw three in a row"
        finally:
            press_key(app, "q")  # the lock is module-scoped state; hand it back off

    def test_unlocked_tool_still_reverts_to_select(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 300, 490, 380)
        wait_for_elements(app, 1)
        sel_class = app.locator("button[title^='Select']").get_attribute("class")
        assert "text-orange-600" in sel_class, "Without the lock the tool must revert to Select"

    def test_lock_button_is_present(self, app: Page):
        expect(app.locator("button[title*='Keep the tool selected']")).to_be_visible()


class TestArrowKeyNudge:
    """Arrow keys move the selection by a pixel, Shift by ten."""

    def test_single_element_nudges_one_pixel_per_press(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 200, 560, 300)
        wait_for_elements(app, 1)
        click_canvas(app, 480, 250)
        start_x = get_elements(app)[0]["x"]
        for _ in range(5):
            press_key(app, "ArrowRight")
        moved = get_elements(app)[0]["x"] - start_x
        assert abs(moved - 5) < 0.51, f"Five presses should travel 5px, travelled {moved}"

    def test_shift_arrow_nudges_ten_pixels(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 200, 560, 300)
        wait_for_elements(app, 1)
        click_canvas(app, 480, 250)
        start_y = get_elements(app)[0]["y"]
        press_key(app, "Shift+ArrowDown")
        moved = get_elements(app)[0]["y"] - start_y
        assert abs(moved - 10) < 0.51, f"Shift+Down should travel 10px, travelled {moved}"

    def test_multi_selection_nudges_every_element(self, app: Page):
        """Each element is written in ONE batch: a per-element write would let
        the last one overwrite the rest and only that shape would move."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 350, 200, 470, 290)
        press_key(app, "5")
        drag_canvas(app, 600, 200, 720, 290)
        wait_for_elements(app, 2)
        press_key(app, "Escape")
        press_key(app, "Control+a")
        before = [el["x"] for el in get_elements(app)]
        for _ in range(4):
            press_key(app, "ArrowLeft")
        after = [el["x"] for el in get_elements(app)]
        for i, (b, a) in enumerate(zip(before, after)):
            assert abs((a - b) + 4) < 0.51, f"element {i} should move -4px, moved {a - b}"

    def test_nudge_carries_bound_arrows_with_the_shape(self, app: Page):
        """The shape and every arrow bound to it move in ONE write. Two separate
        writes in a single keypress would leave the arrow behind."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 350, 200, 470, 290)
        press_key(app, "5")
        drag_canvas(app, 650, 200, 770, 290)
        wait_for_elements(app, 2)
        press_key(app, "Escape")
        press_key(app, "4")
        drag_canvas(app, 470, 245, 648, 245)  # bind the two boxes together
        wait_for_elements(app, 3)
        press_key(app, "Escape")
        click_canvas(app, 700, 245)  # select the right-hand box only
        before = {e["type"]: dict(e) for e in get_elements(app)}
        for _ in range(5):
            press_key(app, "ArrowDown")
        after = {e["type"]: dict(e) for e in get_elements(app)}
        box_moved = after["rectangle"]["y"] - before["rectangle"]["y"]
        assert abs(box_moved - 5) < 0.51, f"the selected box should move 5px, moved {box_moved}"
        arrow_moved = after["arrow"]["y2"] - before["arrow"]["y2"]
        assert abs(arrow_moved - 5) < 1.01, (
            f"the bound arrow endpoint should follow the box, moved {arrow_moved}"
        )


class TestCanvasActionButtons:
    """Undo, redo and zoom-to-fit are reachable with the mouse alone."""

    def test_undo_and_redo_buttons(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 200, 520, 300)
        wait_for_elements(app, 1)
        app.locator("button[title^='Undo']").click()
        wait_for_elements(app, 0)
        app.locator("button[title^='Redo']").click()
        wait_for_elements(app, 1)

    def test_zoom_to_fit_button_frames_the_drawing(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 200, 520, 300)
        wait_for_elements(app, 1)
        press_key(app, "Control+0")
        # Zoom well past the shape, then ask to be brought back to it.
        for _ in range(4):
            app.locator("button", has_text="+").last.click()
            app.wait_for_timeout(100)
        zoomed = int(app.locator("button", has_text="%").text_content().replace("%", ""))
        assert zoomed > 100
        app.locator("button[title^='Zoom to fit']").click()
        app.wait_for_timeout(ACTION_DELAY)
        fitted = int(app.locator("button", has_text="%").text_content().replace("%", ""))
        assert fitted != zoomed, "Zoom to fit should reframe the canvas"
        assert fitted <= 100, f"Fit never zooms past 1:1, got {fitted}%"

    def test_zoom_to_fit_keyboard_shortcut(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 200, 520, 300)
        wait_for_elements(app, 1)
        press_key(app, "Control+0")
        for _ in range(4):
            app.locator("button", has_text="+").last.click()
            app.wait_for_timeout(100)
        press_key(app, "Shift+1")
        app.wait_for_timeout(ACTION_DELAY)
        fitted = int(app.locator("button", has_text="%").text_content().replace("%", ""))
        assert fitted <= 100, f"Shift+1 should frame the drawing, got {fitted}%"


class TestLabelStaysInsideItsShape:
    """A label wraps to the shape's width, so a shape can always be made too
    short for its own text. The shape grows instead of letting the words out."""

    @staticmethod
    def _canvas_offset(page: Page):
        """Measure the canvas-to-page offset instead of assuming it.

        The app fixture is shared by the whole module, so an earlier test may
        have left the viewport panned. Drawing one throwaway shape at known
        page coordinates and reading back where it landed gives the current
        mapping directly."""
        clear_canvas(page)
        press_key(page, "Escape")
        press_key(page, "Control+0")  # zoom back to 1:1 so only the pan differs
        press_key(page, "5")
        drag_canvas(page, 400, 200, 500, 300)
        wait_for_elements(page, 1)
        probe = get_elements(page)[0]
        clear_canvas(page)
        return 400 - probe["x"], 200 - probe["y"]

    def _labelled_box(self, page: Page, text: str):
        clear_canvas(page)
        press_key(page, "Escape")
        press_key(page, "5")
        drag_canvas(page, 400, 200, 640, 330)
        wait_for_elements(page, 1)
        press_key(page, "Escape")
        double_click_canvas(page, 520, 265)
        page.keyboard.type(text, delay=6)
        press_key(page, "Escape")
        page.wait_for_timeout(ACTION_DELAY)
        return get_elements(page)[0]

    def test_shape_grows_when_its_label_needs_more_room(self, app: Page):
        """Asserted as a relative change: the font size is app-wide state that
        earlier tests move, so an absolute height would pass or fail depending
        on what ran before."""
        long_text = "This is a deliberately long label that should wrap inside the box"
        el = self._labelled_box(app, long_text)
        assert el.get("shapeText") == long_text
        h0 = abs(el["height"])
        click_canvas(app, 520, 265)
        for _ in range(6):
            press_key(app, "Control+Shift+Period")
        h1 = abs(get_elements(app)[0]["height"])
        assert h1 > h0, f"a bigger label needs a bigger box, {h0} -> {h1}"

    def test_narrowing_a_labelled_shape_makes_it_taller(self, app: Page):
        """The real failure this guards: a narrower box re-wraps the text to
        MORE lines, so width and height move in opposite directions."""
        off_x, off_y = self._canvas_offset(app)
        el = self._labelled_box(app, "This is a deliberately long label that should wrap inside the box")
        w0, h0 = abs(el["width"]), abs(el["height"])
        # Page coordinates of the shape: canvas origin + measured offset.
        cbox = get_canvas(app).bounding_box()
        sx = cbox["x"] + el["x"] + off_x
        sy = cbox["y"] + el["y"] + off_y
        app.mouse.click(sx + el["width"] / 2, sy + el["height"] / 2)
        app.wait_for_timeout(ACTION_DELAY)
        # drag the SE handle far to the left
        app.mouse.move(sx + el["width"], sy + el["height"])
        app.mouse.down()
        app.mouse.move(sx + 110, sy + el["height"], steps=10)
        app.mouse.up()
        app.wait_for_timeout(ACTION_DELAY * 2)
        el2 = get_elements(app)[0]
        assert abs(el2["width"]) < w0, "the box should have got narrower"
        assert abs(el2["height"]) > h0, (
            f"a narrower box needs more height, went {h0} -> {abs(el2['height'])}"
        )

    def test_an_unlabelled_shape_still_resizes_freely(self, app: Page):
        """The clamp must only apply to shapes that actually carry a label."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 200, 640, 400)
        wait_for_elements(app, 1)
        el = get_elements(app)[0]
        click_canvas(app, 520, 300)
        drag_canvas(app, 640, 400, 500, 260)
        el2 = get_elements(app)[0]
        assert abs(el2["height"]) < abs(el["height"]), (
            "an unlabelled shape must still shrink freely"
        )


class TestStylingAppliesToTheWholeSelection:
    """The style panel has one element id to hand back, but a style change is
    meant for everything selected."""

    def _three_boxes(self, page: Page):
        clear_canvas(page)
        for x in (250, 450, 650):
            press_key(page, "Escape")
            press_key(page, "5")
            drag_canvas(page, x, 250, x + 140, 350)
        wait_for_elements(page, 3)
        press_key(page, "Escape")
        press_key(page, "Control+a")
        page.wait_for_timeout(ACTION_DELAY)

    def test_colour_applies_to_every_selected_shape(self, app: Page):
        self._three_boxes(app)
        app.locator("button[title='#e03131']").first.click()
        app.wait_for_timeout(ACTION_DELAY * 2)
        colours = [e.get("color") for e in get_elements(app)]
        assert colours == ["#e03131"] * 3, f"all three should turn red, got {colours}"

    def test_line_style_applies_to_every_selected_shape(self, app: Page):
        self._three_boxes(app)
        app.locator("button[title='Dashed']").first.click()
        app.wait_for_timeout(ACTION_DELAY * 2)
        styles = [e.get("lineStyle") for e in get_elements(app)]
        assert styles == ["dashed"] * 3, f"all three should go dashed, got {styles}"

    def test_a_single_selection_only_restyles_itself(self, app: Page):
        """Widening to the selection must not leak into the single-select case."""
        clear_canvas(app)
        for x in (300, 600):
            press_key(app, "Escape")
            press_key(app, "5")
            drag_canvas(app, x, 250, x + 140, 350)
        wait_for_elements(app, 2)
        press_key(app, "Escape")
        click_canvas(app, 370, 300)
        app.locator("button[title='#2b8a3e']").first.click()
        app.wait_for_timeout(ACTION_DELAY * 2)
        colours = [e.get("color") for e in get_elements(app)]
        assert colours.count("#2b8a3e") == 1, f"only one should change, got {colours}"


class TestLabelFontSize:
    """Ctrl+Shift+> is advertised in the help dialog; it has to work on a label
    inside a shape, not only on a standalone text element."""

    def _labelled_box(self, page: Page):
        clear_canvas(page)
        press_key(page, "Escape")
        press_key(page, "5")
        drag_canvas(page, 400, 200, 620, 330)
        wait_for_elements(page, 1)
        press_key(page, "Escape")
        double_click_canvas(page, 510, 265)
        page.keyboard.type("Label", delay=20)
        press_key(page, "Escape")
        press_key(page, "Escape")
        click_canvas(page, 510, 265)
        return get_elements(page)[0]

    def test_increase_label_font_size(self, app: Page):
        el = self._labelled_box(app)
        before = el.get("shapeTextFontSize")
        press_key(app, "Control+Shift+Period")
        after = get_elements(app)[0].get("shapeTextFontSize")
        assert after == before + 2, f"font size should rise, {before} -> {after}"

    def test_decrease_label_font_size(self, app: Page):
        el = self._labelled_box(app)
        before = el.get("shapeTextFontSize")
        press_key(app, "Control+Shift+Comma")
        after = get_elements(app)[0].get("shapeTextFontSize")
        assert after == before - 2, f"font size should fall, {before} -> {after}"

    def test_standalone_text_font_size_still_works(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "8")
        click_canvas(app, 400, 300)
        app.keyboard.type("Hello", delay=20)
        press_key(app, "Escape")
        wait_for_elements(app, 1)
        press_key(app, "Escape")
        click_canvas(app, 410, 305)
        before = get_elements(app)[0].get("fontSize")
        press_key(app, "Control+Shift+Period")
        after = get_elements(app)[0].get("fontSize")
        assert after == before + 2, f"text font size should rise, {before} -> {after}"

    def test_a_drawing_saved_before_the_fix_heals_on_open(self, app: Page):
        """A shape authored elsewhere -- by the MCP tools, the agent, or an older
        build -- never passed through the editor, so nothing checked that its box
        could hold its label. Opening it is the last chance to notice."""
        clear_canvas(app)
        app.evaluate(
            """() => localStorage.setItem('jasketch_elements', JSON.stringify([{
                type: "rectangle", x: 120, y: 80, width: 200, height: 40, id: "legacy-1",
                color: "#000000", strokeWidth: 2, fillColor: "transparent",
                lineStyle: "solid", opacity: 1,
                shapeText: "A long label that cannot possibly fit inside forty pixels",
                shapeTextColor: "#000000", shapeTextFontSize: 20, shapeTextFontFamily: "Virgil"
            }]))"""
        )
        app.reload(wait_until="load")
        get_canvas(app).wait_for(state="visible", timeout=APP_READY_TIMEOUT)
        app.wait_for_timeout(ACTION_DELAY * 4)
        el = get_elements(app)[0]
        assert abs(el["height"]) > 40, (
            f"a too-short legacy shape should heal on open, height is {el['height']}"
        )
        assert el.get("shapeText"), "the label itself must survive the repair"


class TestGeometryIsNormalised:
    """A shape dragged out bottom-up or right-to-left used to store a negative
    size, which left its selection outline sitting away from the shape."""

    @pytest.mark.parametrize(
        "name,x1,y1,x2,y2",
        [
            ("top-left to bottom-right", 400, 200, 550, 300),
            ("bottom-right to top-left", 550, 300, 400, 200),
            ("top-right to bottom-left", 550, 200, 400, 300),
            ("bottom-left to top-right", 400, 300, 550, 200),
        ],
    )
    def test_drawn_in_any_direction_stores_a_positive_size(
        self, app: Page, name: str, x1: int, y1: int, x2: int, y2: int
    ):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, x1, y1, x2, y2)
        wait_for_elements(app, 1)
        el = get_elements(app)[0]
        assert el["width"] > 0 and el["height"] > 0, (
            f"{name} stored {el['width']}x{el['height']}"
        )


class TestStylePanelFollowsEverySelection:
    """The panel keys off a primary element. Every path that builds a selection
    has to set one, or the controls silently vanish."""

    @staticmethod
    def _swatches(page: Page) -> int:
        return page.evaluate(
            """() => [...document.querySelectorAll('button')]
                 .filter(b => /^#/.test(b.getAttribute('title') || '')).length"""
        )

    def test_rubber_band_selection_keeps_the_style_panel(self, app: Page):
        clear_canvas(app)
        for x in (300, 500):
            press_key(app, "Escape")
            press_key(app, "5")
            drag_canvas(app, x, 250, x + 120, 350)
        wait_for_elements(app, 2)
        press_key(app, "Escape")
        drag_canvas(app, 250, 200, 700, 420)   # rubber-band around both
        assert self._swatches(app) > 0, "box-selecting two shapes hid the style panel"

    def test_select_all_keeps_the_style_panel(self, app: Page):
        clear_canvas(app)
        for x in (300, 500):
            press_key(app, "Escape")
            press_key(app, "5")
            drag_canvas(app, x, 250, x + 120, 350)
        wait_for_elements(app, 2)
        press_key(app, "Escape")
        press_key(app, "Control+a")
        assert self._swatches(app) > 0, "Ctrl+A hid the style panel"


class TestMenuDropdown:
    def test_closes_on_an_outside_click(self, app: Page):
        app.locator("button[title='Menu']").click()
        app.wait_for_timeout(ACTION_DELAY)
        assert app.get_by_text("Keyboard shortcuts").is_visible()
        get_canvas(app).click(position={"x": 700, "y": 500}, force=True)
        app.wait_for_timeout(ACTION_DELAY * 2)
        assert not app.get_by_text("Keyboard shortcuts").is_visible(), (
            "the menu stayed open over the canvas after clicking away"
        )

    def test_closes_on_escape(self, app: Page):
        app.locator("button[title='Menu']").click()
        app.wait_for_timeout(ACTION_DELAY)
        press_key(app, "Escape")
        app.wait_for_timeout(ACTION_DELAY)
        assert not app.get_by_text("Keyboard shortcuts").is_visible()


class TestLabelEditorWraps:
    """While typing, the label used to run off the side of the shape and get
    clipped -- so you could not read what you were writing."""

    def test_editor_wraps_instead_of_clipping(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 300, 250, 430, 340)
        wait_for_elements(app, 1)
        press_key(app, "Escape")
        double_click_canvas(app, 365, 295)
        app.keyboard.type("erfjhsdkjf idisoncsd skdvcnksdjvn ksjdvnksjdnv", delay=8)
        app.wait_for_timeout(ACTION_DELAY)
        editor = app.locator("textarea").last
        metrics = editor.evaluate(
            "n => ({sw: n.scrollWidth, cw: n.clientWidth, sh: n.scrollHeight, ch: n.clientHeight})"
        )
        assert metrics["sw"] <= metrics["cw"] + 1, "the label editor clipped horizontally"
        assert metrics["sh"] <= metrics["ch"] + 1, "the label editor clipped vertically"
        press_key(app, "Escape")

    def test_shape_grows_while_the_label_is_typed(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 300, 250, 430, 340)
        wait_for_elements(app, 1)
        h0 = abs(get_elements(app)[0]["height"])
        press_key(app, "Escape")
        double_click_canvas(app, 365, 295)
        app.keyboard.type("a label long enough that it has to wrap several times over", delay=8)
        app.wait_for_timeout(ACTION_DELAY * 2)
        h1 = abs(get_elements(app)[0]["height"])
        assert h1 > h0, f"the box should grow as the label is typed, {h0} -> {h1}"
        press_key(app, "Escape")


class TestAlignmentSnapping:
    """Dragging a shape close to a neighbour lines the two up exactly."""

    def _two_stacked_boxes(self, page: Page):
        clear_canvas(page)
        press_key(page, "Escape")
        press_key(page, "5")
        drag_canvas(page, 300, 200, 450, 300)
        press_key(page, "Escape")
        press_key(page, "5")
        drag_canvas(page, 300, 420, 450, 520)
        wait_for_elements(page, 2)
        press_key(page, "Escape")
        return sorted(get_elements(page), key=lambda e: e["y"])

    def test_a_near_miss_snaps_into_line(self, app: Page):
        top, bottom = self._two_stacked_boxes(app)
        assert abs(bottom["x"] - top["x"]) < 0.01
        drag_canvas(app, 375, 470, 379, 470)   # 4px right: within the snap radius
        moved = sorted(get_elements(app), key=lambda e: e["y"])[1]
        assert abs(moved["x"] - top["x"]) < 0.6, (
            f"a 4px near-miss should snap back into line, x is {moved['x']}"
        )

    def test_ctrl_suppresses_snapping(self, app: Page):
        """There has to be a way to put a shape exactly where you want it."""
        top, bottom = self._two_stacked_boxes(app)
        start_x = bottom["x"]
        box = get_canvas(app).bounding_box()
        app.mouse.move(box["x"] + 375, box["y"] + 470)
        app.mouse.down()
        app.keyboard.down("Control")
        app.mouse.move(box["x"] + 379, box["y"] + 470, steps=8)
        app.mouse.up()
        app.keyboard.up("Control")
        app.wait_for_timeout(ACTION_DELAY)
        moved = sorted(get_elements(app), key=lambda e: e["y"])[1]
        assert abs(moved["x"] - (start_x + 4)) < 1.5, (
            f"Ctrl should suppress the snap, x is {moved['x']} (wanted {start_x + 4})"
        )


class TestConnectorLabels:
    """A flowchart's meaning lives on its arrows ("yes", "no", "on failure").
    Before this the only way to write that was a floating text element that did
    not travel with the arrow."""

    def _labelled_arrow(self, page: Page, text: str = "Get money"):
        clear_canvas(page)
        press_key(page, "Escape")
        press_key(page, "4")
        drag_canvas(page, 400, 250, 400, 450)
        wait_for_elements(page, 1)
        press_key(page, "Escape")
        double_click_canvas(page, 400, 350)
        page.keyboard.type(text, delay=15)
        press_key(page, "Escape")
        page.wait_for_timeout(ACTION_DELAY)
        return get_elements(page)[0]

    def test_double_click_labels_an_arrow(self, app: Page):
        el = self._labelled_arrow(app)
        assert el["type"] == "arrow"
        assert el.get("shapeText") == "Get money"

    def test_labelling_leaves_the_geometry_alone(self, app: Page):
        """fit_shape_to_label grows boxes; a connector has no height to grow and
        must not pick up a NaN one."""
        el = self._labelled_arrow(app)
        for key in ("x1", "y1", "x2", "y2"):
            assert el[key] == el[key], f"{key} became NaN"
        assert el.get("height") in (None, 0) or el["height"] == el["height"]

    def test_the_label_can_be_edited_again(self, app: Page):
        self._labelled_arrow(app)
        press_key(app, "Escape")
        double_click_canvas(app, 400, 350)
        value = app.locator("textarea").last.input_value()
        assert "Get money" in value
        press_key(app, "Escape")

    def test_the_label_survives_the_arrow_moving(self, app: Page):
        self._labelled_arrow(app)
        press_key(app, "Escape")
        click_canvas(app, 400, 350)
        for _ in range(3):
            press_key(app, "Shift+ArrowRight")
        el = get_elements(app)[0]
        assert el.get("shapeText") == "Get money"


class TestConnectorHitTolerance:
    """The old test measured |d1 + d2 - length|, which is an ellipse through the
    endpoints rather than a corridor along the line: on a long connector it
    accepted clicks tens of pixels away."""

    def _one_arrow(self, page: Page):
        clear_canvas(page)
        press_key(page, "Escape")
        press_key(page, "4")
        drag_canvas(page, 400, 300, 700, 300)
        wait_for_elements(page, 1)
        press_key(page, "Escape")

    def _selects_at(self, page: Page, x: int, y: int) -> bool:
        get_canvas(page).click(position={"x": 1100, "y": 650}, force=True)  # deselect
        page.wait_for_timeout(150)
        before = get_elements(page)[0]["y1"]
        get_canvas(page).click(position={"x": x, "y": y}, force=True)
        page.wait_for_timeout(200)
        press_key(page, "ArrowDown")
        hit = abs(get_elements(page)[0]["y1"] - before) > 0.01
        if hit:
            press_key(page, "ArrowUp")
        return hit

    def test_a_click_on_the_line_selects_it(self, app: Page):
        self._one_arrow(app)
        assert self._selects_at(app, 550, 303), "a click on the connector should select it"

    @pytest.mark.parametrize("offset", [20, 40])
    def test_a_click_well_clear_of_the_line_does_not(self, app: Page, offset: int):
        self._one_arrow(app)
        assert not self._selects_at(app, 550, 300 + offset), (
            f"a click {offset}px from the connector should be ignored"
        )


class TestGestureFollowsThePointer:
    """A drag belongs to the pointer, not to the element it began on. Crossing
    onto the sidebar used to stall the drag and swallow the release."""

    def test_a_drag_survives_crossing_the_sidebar(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 600, 300, 760, 400)
        wait_for_elements(app, 1)
        press_key(app, "Escape")
        click_canvas(app, 680, 350)
        x0 = get_elements(app)[0]["x"]
        box = get_canvas(app).bounding_box()
        app.mouse.move(box["x"] + 680, box["y"] + 350)
        app.mouse.down()
        app.mouse.move(box["x"] + 400, box["y"] + 350, steps=8)
        app.mouse.move(box["x"] + 60, box["y"] + 350, steps=8)   # over the sidebar
        app.mouse.move(box["x"] + 500, box["y"] + 420, steps=8)  # and back
        app.mouse.up()
        app.wait_for_timeout(ACTION_DELAY)
        x1 = get_elements(app)[0]["x"]
        assert abs(x1 - x0) > 50, f"the drag stalled crossing the panel: {x0} -> {x1}"

    def test_releasing_over_the_sidebar_ends_the_drag(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 600, 300, 760, 400)
        wait_for_elements(app, 1)
        press_key(app, "Escape")
        click_canvas(app, 680, 350)
        box = get_canvas(app).bounding_box()
        app.mouse.move(box["x"] + 680, box["y"] + 350)
        app.mouse.down()
        app.mouse.move(box["x"] + 80, box["y"] + 350, steps=10)
        app.mouse.up()                       # released over the panel
        app.wait_for_timeout(ACTION_DELAY)
        settled = get_elements(app)[0]["x"]
        app.mouse.move(box["x"] + 700, box["y"] + 600)   # no button held
        app.mouse.move(box["x"] + 780, box["y"] + 650, steps=6)
        app.wait_for_timeout(ACTION_DELAY)
        assert abs(get_elements(app)[0]["x"] - settled) < 0.5, (
            "the shape kept following the pointer after the button was released"
        )


class TestDialogDismissal:
    def test_share_dialog_closes_on_escape(self, app: Page):
        app.locator("button[title='Shareable link']").click()
        app.wait_for_timeout(ACTION_DELAY)
        assert app.get_by_text("Share Canvas").is_visible()
        press_key(app, "Escape")
        app.wait_for_timeout(ACTION_DELAY)
        assert app.get_by_text("Share Canvas").count() == 0

    def test_share_dialog_closes_on_a_backdrop_click(self, app: Page):
        app.locator("button[title='Shareable link']").click()
        app.wait_for_timeout(ACTION_DELAY)
        # The backdrop is fixed inset-0, so a corner is always on it and always
        # inside the viewport whatever size the test window happens to be.
        app.mouse.click(20, 20)
        app.wait_for_timeout(ACTION_DELAY)
        assert app.get_by_text("Share Canvas").count() == 0


class TestGroupingAndLayering:
    """These are all reached from the keydown listener, whose closure only
    refreshes when the ELEMENT list changes -- so anything that read the
    selection from it saw the state from before the selection was made."""

    def _three_boxes(self, page: Page):
        clear_canvas(page)
        for i in range(3):
            press_key(page, "Escape")
            press_key(page, "5")
            drag_canvas(page, 300 + i * 110, 250, 300 + i * 110 + 90, 320)
        wait_for_elements(page, 3)
        press_key(page, "Escape")
        press_key(page, "Control+a")
        page.wait_for_timeout(ACTION_DELAY)

    def test_select_all_then_group(self, app: Page):
        self._three_boxes(app)
        press_key(app, "Control+g")
        app.wait_for_timeout(ACTION_DELAY)
        grouped = [e for e in get_elements(app) if e.get("groupId")]
        assert len(grouped) == 3, f"Ctrl+A then Ctrl+G grouped {len(grouped)}/3"

    def test_select_all_then_duplicate(self, app: Page):
        self._three_boxes(app)
        press_key(app, "Control+d")
        app.wait_for_timeout(ACTION_DELAY * 2)
        assert get_elements_count(app) == 6, "Ctrl+A then Ctrl+D should duplicate all three"

    def test_layering_works_in_both_directions(self, app: Page):
        """bring-to-front used to do removeElement then addElement -- two writes
        in one tick that cancelled each other out."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 300, 250, 500, 400)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 360, 300, 560, 450)
        wait_for_elements(app, 2)
        original = [e["id"] for e in get_elements(app)]
        press_key(app, "Escape")
        click_canvas(app, 530, 430)
        press_key(app, "Control+BracketLeft")
        app.wait_for_timeout(ACTION_DELAY)
        sent_back = [e["id"] for e in get_elements(app)]
        assert sent_back != original, "send to back did not reorder"
        press_key(app, "Control+BracketRight")
        app.wait_for_timeout(ACTION_DELAY)
        assert [e["id"] for e in get_elements(app)] == original, (
            "bring to front did not undo the send to back"
        )

    def test_layering_keeps_the_selection(self, app: Page):
        """Clearing it meant you could not layer twice in a row."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 250, 540, 340)
        wait_for_elements(app, 1)
        press_key(app, "Escape")
        click_canvas(app, 470, 295)
        press_key(app, "Control+BracketLeft")
        app.wait_for_timeout(ACTION_DELAY)
        x0 = get_elements(app)[0]["x"]
        press_key(app, "ArrowRight")
        assert abs(get_elements(app)[0]["x"] - x0 - 1) < 0.6, (
            "the shape was deselected by the layer change"
        )


class TestRapidDrawing:
    def test_twelve_shapes_drawn_quickly_all_land(self, app: Page):
        """Every mutation used to rebuild from the render-time element list, so
        two in one tick meant the second discarded the first."""
        clear_canvas(app)
        box = get_canvas(app).bounding_box()
        for i in range(12):
            press_key(app, "Escape")
            press_key(app, "5")
            app.mouse.move(box["x"] + 300 + i * 58, box["y"] + 250)
            app.mouse.down()
            app.mouse.move(box["x"] + 300 + i * 58 + 48, box["y"] + 310, steps=3)
            app.mouse.up()
            app.wait_for_timeout(40)
        wait_for_elements(app, 12, timeout=8000)
        assert get_elements_count(app) == 12


class TestConnectorLabelRoundTrip:
    def test_a_connector_label_survives_save_and_load(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 400, 250, 540, 340)
        wait_for_elements(app, 1)
        press_key(app, "Escape")
        double_click_canvas(app, 470, 295)
        app.keyboard.type("Box A", delay=12)
        press_key(app, "Escape")
        press_key(app, "Escape")
        press_key(app, "4")
        drag_canvas(app, 560, 300, 700, 300)
        wait_for_elements(app, 2)
        press_key(app, "Escape")
        double_click_canvas(app, 630, 300)
        app.keyboard.type("yes", delay=12)
        press_key(app, "Escape")
        app.wait_for_timeout(ACTION_DELAY)

        with app.expect_download(timeout=15000) as dl:
            press_key(app, "Control+s")
        saved = "/tmp/jasketch-roundtrip.jasketch"
        dl.value.save_as(saved)

        clear_canvas(app)
        # index 1 is the .jasketch input; index 0 accepts images
        app.locator("input[type=file]").nth(1).set_input_files(saved)
        app.wait_for_timeout(ACTION_DELAY * 6)
        restored = {e["type"]: e.get("shapeText") for e in get_elements(app)}
        assert restored.get("rectangle") == "Box A", f"shape label lost: {restored}"
        assert restored.get("arrow") == "yes", f"connector label lost: {restored}"


class TestNoJunkElements:
    def test_a_bare_click_with_a_shape_tool_creates_nothing(self, app: Page):
        """A click rather than a drag left an invisible zero-size element behind
        that could still be selected, counted and exported."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        click_canvas(app, 500, 300)
        app.wait_for_timeout(ACTION_DELAY)
        assert get_elements_count(app) == 0

    def test_escape_mid_drag_cancels_the_shape(self, app: Page):
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        box = get_canvas(app).bounding_box()
        app.mouse.move(box["x"] + 400, box["y"] + 250)
        app.mouse.down()
        app.mouse.move(box["x"] + 560, box["y"] + 350, steps=6)
        press_key(app, "Escape")
        app.mouse.up()
        app.wait_for_timeout(ACTION_DELAY)
        assert get_elements_count(app) == 0


class TestDeletingClearsBindings:
    def test_deleting_a_shape_unbinds_its_arrows(self, app: Page):
        """An arrow bound to a deleted shape kept a binding naming a ghost."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 300, 250, 430, 330)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 650, 250, 780, 330)
        press_key(app, "Escape")
        press_key(app, "4")
        drag_canvas(app, 432, 290, 648, 290)
        wait_for_elements(app, 3)
        press_key(app, "Escape")
        click_canvas(app, 710, 290)      # the right-hand box
        press_key(app, "Delete")
        app.wait_for_timeout(ACTION_DELAY)
        arrows = [e for e in get_elements(app) if e["type"] == "arrow"]
        assert arrows, "the arrow itself should still be there"
        assert not arrows[0].get("endBinding"), "the binding to the deleted shape was kept"


class TestPointerFeedback:
    """Nothing distinguished "you will move this", "you will resize it" and
    "you will start a selection box" until after you had committed to it."""

    def _one_shape(self, page: Page):
        clear_canvas(page)
        press_key(page, "Escape")
        press_key(page, "5")
        drag_canvas(page, 400, 250, 560, 350)
        wait_for_elements(page, 1)
        press_key(page, "Escape")
        press_key(page, "1")

    @staticmethod
    def _cursor(page: Page) -> str:
        return page.evaluate("() => getComputedStyle(document.querySelector('canvas')).cursor")

    def _hover(self, page: Page, x: int, y: int):
        box = get_canvas(page).bounding_box()
        page.mouse.move(box["x"] + x, box["y"] + y)
        page.wait_for_timeout(ACTION_DELAY)

    def test_cursor_reflects_what_a_click_would_do(self, app: Page):
        self._one_shape(app)
        self._hover(app, 900, 600)
        empty = self._cursor(app)
        self._hover(app, 480, 300)
        over = self._cursor(app)
        assert over != empty, f"cursor did not change over a shape ({empty})"
        assert over == "move", f"expected a move cursor over a shape, got {over}"

    def test_cursor_shows_resize_and_rotate_on_the_handles(self, app: Page):
        self._one_shape(app)
        click_canvas(app, 480, 300)
        self._hover(app, 560, 350)
        assert self._cursor(app) == "nwse-resize", f"corner handle gave {self._cursor(app)}"
        self._hover(app, 480, 225)
        assert self._cursor(app) == "grab", f"rotate handle gave {self._cursor(app)}"

    def test_hovering_outlines_the_shape_that_would_be_picked(self, app: Page):
        self._one_shape(app)
        click_canvas(app, 950, 620)          # deselect first
        self._hover(app, 950, 620)
        away = app.screenshot(clip={"x": 380, "y": 230, "width": 220, "height": 150})
        self._hover(app, 480, 300)
        over = app.screenshot(clip={"x": 380, "y": 230, "width": 220, "height": 150})
        assert over != away, "hovering a shape showed no hint"
        self._hover(app, 950, 620)
        assert app.screenshot(clip={"x": 380, "y": 230, "width": 220, "height": 150}) == away, (
            "the hover outline was left behind after moving away"
        )


class TestInspectorLayout:
    """The properties panel moved to the right and became part of the layout
    rather than a card floating over the drawing."""

    def test_the_canvas_is_not_covered_by_the_panel(self, app: Page):
        """The old left panel sat ON the canvas, so its whole footprint was a
        dead zone: a mousedown there never reached the drawing surface."""
        # Arm a drawing tool so there is something to configure -- with select
        # and nothing selected the inspector is deliberately absent.
        press_key(app, "Escape")
        press_key(app, "5")
        app.wait_for_timeout(ACTION_DELAY)
        geo = app.evaluate(
            """() => {
                const c = document.querySelector('canvas').getBoundingClientRect();
                const s = document.querySelector('.sidebar');
                return {cx: c.x, cw: c.width, sx: s ? s.getBoundingClientRect().x : null};
            }"""
        )
        assert geo["cx"] == 0, "the canvas should start at the left edge"
        assert geo["sx"] is not None, "the inspector should always be present"
        assert geo["cw"] <= geo["sx"] + 2, "the canvas runs underneath the inspector"

    def test_the_far_left_of_the_canvas_is_drawable(self, app: Page):
        """This is the dead zone, tested directly."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        drag_canvas(app, 60, 300, 200, 400)
        wait_for_elements(app, 1)
        assert get_elements_count(app) == 1

    def test_the_inspector_shows_defaults_with_nothing_selected(self, app: Page):
        """Setting a colour and then drawing has to keep working, which is why
        this is a permanent panel and not a selection popup."""
        clear_canvas(app)
        press_key(app, "Escape")
        press_key(app, "5")
        inspector = app.locator(".sidebar")
        expect(inspector).to_be_visible()
        expect(inspector.get_by_text("Defaults", exact=True)).to_be_visible()
        swatches = app.evaluate(
            """() => [...document.querySelectorAll('.sidebar button')]
                 .filter(b => /^#/.test(b.getAttribute('title') || '')).length"""
        )
        assert swatches > 0, "no colour controls with nothing selected"

    def test_collapsing_gives_the_canvas_the_full_width(self, app: Page):
        """The canvas has to re-measure: folding the panel away changes its
        container without firing a window resize."""
        full = app.evaluate("() => innerWidth")
        app.locator("button[title*='inspector']").click()
        app.wait_for_timeout(ACTION_DELAY * 2)
        widened = app.evaluate("() => document.querySelector('canvas').getBoundingClientRect().width")
        assert abs(widened - full) < 2, f"canvas did not reclaim the space: {widened} of {full}"
        app.locator("button[title*='inspector']").click()
        app.wait_for_timeout(ACTION_DELAY * 2)
        restored = app.evaluate("() => document.querySelector('canvas').getBoundingClientRect().width")
        assert restored < full, "the inspector did not come back"
