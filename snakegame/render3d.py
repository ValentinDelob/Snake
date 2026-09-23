"""Software 3D renderer.

There is no OpenGL dependency on purpose: the executable must start on any
machine, including remote sessions without a GPU driver. Instead the board is
rasterised with pygame polygons using classic real-time 3D maths:

* a camera with a position, a target and a vertical field of view
* a perspective projection into screen space
* back-face culling, then a painter's algorithm (far faces first)
* Lambert shading from a single directional light

World axes: X grows to the right, Z grows away from the player (it maps to
the grid row), Y is up. One grid cell is one world unit.
"""

from __future__ import annotations

import math
from enum import Enum
from typing import Optional, Sequence

import pygame

from . import config
from .geometry import Point

Vec3 = tuple[float, float, float]

WORLD_UP: Vec3 = (0.0, 1.0, 0.0)
LIGHT_DIR: Vec3 = (0.35, 0.86, -0.37)


# --------------------------------------------------------------------------- #
# Vector helpers (plain tuples: allocating objects per frame is too slow)
# --------------------------------------------------------------------------- #
def sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def scale(a: Vec3, k: float) -> Vec3:
    return (a[0] * k, a[1] * k, a[2] * k)


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def normalize(a: Vec3) -> Vec3:
    length = math.sqrt(dot(a, a))
    if length < 1e-9:
        return (0.0, 0.0, 1.0)
    return (a[0] / length, a[1] / length, a[2] / length)


def lerp3(a: Vec3, b: Vec3, t: float) -> Vec3:
    t = max(0.0, min(1.0, t))
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def shade(color: tuple[int, int, int], normal: Vec3, boost: float = 0.0) -> tuple[int, int, int]:
    """Ambient + Lambert diffuse, clamped."""
    intensity = 0.42 + 0.58 * max(0.0, dot(normal, LIGHT_DIR)) + boost
    return (
        min(255, int(color[0] * intensity)),
        min(255, int(color[1] * intensity)),
        min(255, int(color[2] * intensity)),
    )


# --------------------------------------------------------------------------- #
# Clipping (Sutherland-Hodgman)
# --------------------------------------------------------------------------- #
def clip_near(view_points: Sequence[Vec3], near: float) -> list[Vec3]:
    """Clip a camera-space polygon against the near plane z = near."""
    result: list[Vec3] = []
    count = len(view_points)
    for index in range(count):
        current = view_points[index]
        following = view_points[(index + 1) % count]
        current_in = current[2] >= near
        following_in = following[2] >= near
        if current_in:
            result.append(current)
        if current_in != following_in:
            span = following[2] - current[2]
            t = 0.0 if span == 0.0 else (near - current[2]) / span
            result.append(
                (
                    current[0] + (following[0] - current[0]) * t,
                    current[1] + (following[1] - current[1]) * t,
                    near,
                )
            )
    return result


Point2 = tuple[float, float]


def _clip_half_plane(
    points: Sequence[Point2], axis: int, limit: float, keep_greater: bool
) -> list[Point2]:
    result: list[Point2] = []
    count = len(points)
    for index in range(count):
        current = points[index]
        following = points[(index + 1) % count]
        current_in = current[axis] >= limit if keep_greater else current[axis] <= limit
        following_in = following[axis] >= limit if keep_greater else following[axis] <= limit
        if current_in:
            result.append(current)
        if current_in != following_in:
            span = following[axis] - current[axis]
            t = 0.0 if span == 0.0 else (limit - current[axis]) / span
            result.append(
                (
                    current[0] + (following[0] - current[0]) * t,
                    current[1] + (following[1] - current[1]) * t,
                )
            )
    return result


def clip_to_rect(points: Sequence[Point2], rect: pygame.Rect) -> list[Point2]:
    """Clip a screen polygon to the viewport, leaving coordinates bounded."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    if max(xs) < rect.left or min(xs) > rect.right or max(ys) < rect.top or min(ys) > rect.bottom:
        return []  # fully outside
    if (
        min(xs) >= rect.left
        and max(xs) <= rect.right
        and min(ys) >= rect.top
        and max(ys) <= rect.bottom
    ):
        return list(points)  # fully inside: the common case, no work needed

    clipped: list[Point2] = list(points)
    for axis, limit, keep_greater in (
        (0, float(rect.left), True),
        (0, float(rect.right), False),
        (1, float(rect.top), True),
        (1, float(rect.bottom), False),
    ):
        clipped = _clip_half_plane(clipped, axis, limit, keep_greater)
        if len(clipped) < 3:
            return []
    return clipped


# --------------------------------------------------------------------------- #
class Camera:
    """Pinhole camera projecting world points into a viewport."""

    def __init__(self, eye: Vec3, target: Vec3, fov_deg: float = 55.0, near: float = 0.25) -> None:
        self.eye = eye
        self.target = target
        self.fov_deg = fov_deg
        self.near = near
        self.viewport = pygame.Rect(0, 0, 1, 1)
        self._right: Vec3 = (1.0, 0.0, 0.0)
        self._up: Vec3 = (0.0, 1.0, 0.0)
        self._forward: Vec3 = (0.0, 0.0, 1.0)
        self._focal = 1.0
        self._center = (0.0, 0.0)

    def prepare(self, viewport: pygame.Rect) -> None:
        """Recompute the basis and the focal length for this viewport."""
        forward = normalize(sub(self.target, self.eye))
        right = cross(forward, WORLD_UP)
        if dot(right, right) < 1e-8:  # looking straight up or down
            right = (1.0, 0.0, 0.0)
        right = normalize(right)
        self._forward = forward
        self._right = right
        self._up = cross(right, forward)
        self._focal = (viewport.height / 2.0) / math.tan(math.radians(self.fov_deg) / 2.0)
        self._center = (viewport.centerx, viewport.centery)
        self.viewport = viewport

    def to_view(self, point: Vec3) -> Vec3:
        """World point expressed in camera space (z grows in front of the eye)."""
        d = sub(point, self.eye)
        return (dot(d, self._right), dot(d, self._up), dot(d, self._forward))

    def project_view(self, view_point: Vec3) -> tuple[float, float]:
        """Project a camera-space point that is already in front of the eye."""
        factor = self._focal / view_point[2]
        return (self._center[0] + view_point[0] * factor, self._center[1] - view_point[1] * factor)

    def project(self, point: Vec3) -> Optional[tuple[float, float, float]]:
        """Return (screen_x, screen_y, depth) or None when behind the camera."""
        view = self.to_view(point)
        if view[2] <= self.near:
            return None
        x, y = self.project_view(view)
        return (x, y, view[2])


# --------------------------------------------------------------------------- #
class FaceBatch:
    """Collects shaded polygons and paints them far-to-near."""

    def __init__(self, camera: Camera) -> None:
        self.camera = camera
        self._faces: list[tuple[float, list[tuple[float, float]], tuple[int, int, int]]] = []

    def add(
        self,
        points: Sequence[Vec3],
        normal: Vec3,
        color: tuple[int, int, int],
        boost: float = 0.0,
        cull: bool = True,
    ) -> None:
        camera = self.camera
        if cull:
            # A face is visible when its normal points towards the camera.
            to_camera = sub(camera.eye, points[0])
            if dot(normal, to_camera) <= 0.0:
                return

        view = [camera.to_view(point) for point in points]
        if min(v[2] for v in view) < camera.near:
            view = clip_near(view, camera.near)
            if len(view) < 3:
                return  # entirely behind the eye

        depth = sum(v[2] for v in view) / len(view)
        screen = [camera.project_view(v) for v in view]

        # Filling a polygon that spans millions of pixels costs seconds, so the
        # geometry is clipped to the viewport before it ever reaches pygame.
        screen = clip_to_rect(screen, camera.viewport)
        if len(screen) < 3:
            return

        self._faces.append((depth, screen, shade(color, normal, boost)))

    def add_cube(
        self,
        center: Vec3,
        half: float,
        color: tuple[int, int, int],
        boost: float = 0.0,
        yaw: float = 0.0,
        half_y: Optional[float] = None,
    ) -> None:
        """Axis-aligned (or yaw-rotated) box."""
        hy = half if half_y is None else half_y
        cos_y, sin_y = math.cos(yaw), math.sin(yaw)

        def vertex(sx: float, sy: float, sz: float) -> Vec3:
            x, z = sx * half, sz * half
            rx = x * cos_y - z * sin_y
            rz = x * sin_y + z * cos_y
            return (center[0] + rx, center[1] + sy * hy, center[2] + rz)

        def normal(nx: float, ny: float, nz: float) -> Vec3:
            rx = nx * cos_y - nz * sin_y
            rz = nx * sin_y + nz * cos_y
            return (rx, ny, rz)

        # (corners, normal) for the six faces, counter-clockwise seen from outside
        faces = (
            (((-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1)), (0, 1, 0)),      # top
            (((-1, -1, 1), (1, -1, 1), (1, -1, -1), (-1, -1, -1)), (0, -1, 0)),  # bottom
            (((-1, 1, 1), (1, 1, 1), (1, -1, 1), (-1, -1, 1)), (0, 0, 1)),      # front (+Z)
            (((1, 1, -1), (-1, 1, -1), (-1, -1, -1), (1, -1, -1)), (0, 0, -1)),  # back
            (((1, 1, 1), (1, 1, -1), (1, -1, -1), (1, -1, 1)), (1, 0, 0)),      # right
            (((-1, 1, -1), (-1, 1, 1), (-1, -1, 1), (-1, -1, -1)), (-1, 0, 0)),  # left
        )
        for corners, n in faces:
            self.add([vertex(*c) for c in corners], normal(*n), color, boost)

    def flush(self, surface: pygame.Surface) -> int:
        """Draw everything collected, farthest first. Returns the face count."""
        self._faces.sort(key=lambda face: -face[0])
        for _, points, color in self._faces:
            pygame.draw.polygon(surface, color, points)
        count = len(self._faces)
        self._faces.clear()
        return count


# --------------------------------------------------------------------------- #
class CameraMode(Enum):
    FOLLOW = "follow"      # 3/4 view trailing the head, fixed orientation
    OVERVIEW = "overview"  # the whole board at once
    CHASE = "chase"        # behind the head, turns with it (relative steering)

    @property
    def uses_relative_steering(self) -> bool:
        return self is CameraMode.CHASE

    def next(self) -> "CameraMode":
        members = list(CameraMode)
        return members[(members.index(self) + 1) % len(members)]


class Board3DRenderer:
    """Draws the snake board as a lit 3D scene."""

    name = "3d"

    def __init__(self, mode: CameraMode = CameraMode.FOLLOW) -> None:
        self.mode = mode
        self.camera = Camera(eye=(14.0, 16.0, 30.0), target=(14.0, 0.0, 9.0))
        self.batch = FaceBatch(self.camera)
        self.face_count = 0
        self._eye: Optional[Vec3] = None
        self._target: Optional[Vec3] = None
        self._sky_surface: Optional[pygame.Surface] = None

    # ------------------------------------------------------------------ #
    @staticmethod
    def cell_center(cell: Point, y: float = 0.0) -> Vec3:
        return (cell.x + 0.5, y, cell.y + 0.5)

    #: vertical field of view per camera, tuned so the board fills the frame
    FOV = {CameraMode.FOLLOW: 55.0, CameraMode.OVERVIEW: 50.0, CameraMode.CHASE: 62.0}

    def desired_camera(self, world) -> tuple[Vec3, Vec3]:
        width, height = float(world.width), float(world.height)
        head = self.cell_center(world.head, 0.5)

        if self.mode is CameraMode.OVERVIEW:
            target = (width / 2.0, 0.0, height / 2.0)
            return add(target, (0.0, 20.0, 11.5)), target

        if self.mode is CameraMode.CHASE:
            forward = (float(world.direction.x), 0.0, float(world.direction.y))
            eye = add(add(head, scale(forward, -5.0)), (0.0, 3.0, 0.0))
            target = add(add(head, scale(forward, 4.5)), (0.0, 0.1, 0.0))
            return eye, target

        # FOLLOW: keep the head roughly centred but never leave the board edges
        target = (
            min(max(head[0], 7.0), max(7.0, width - 7.0)),
            0.0,
            min(max(head[2], 4.5), max(4.5, height - 4.5)),
        )
        return add(target, (0.0, 12.0, 8.0)), target

    def update(self, dt: float, world) -> None:
        """Smoothly move the camera towards its target pose."""
        eye, target = self.desired_camera(world)
        if self._eye is None or self._target is None:
            self._eye, self._target = eye, target
        else:
            smoothing = 1.0 - math.exp(-dt * (5.5 if self.mode is CameraMode.CHASE else 4.0))
            self._eye = lerp3(self._eye, eye, smoothing)
            self._target = lerp3(self._target, target, smoothing)
        self.camera.eye = self._eye
        self.camera.target = self._target
        self.camera.fov_deg = self.FOV[self.mode]

    def reset_camera(self) -> None:
        self._eye = None
        self._target = None

    def set_mode(self, mode: CameraMode) -> None:
        self.mode = mode
        self.reset_camera()

    # ------------------------------------------------------------------ #
    def draw(self, surface: pygame.Surface, world, elapsed: float, flash: float = 0.0) -> None:
        viewport = pygame.Rect(config.BOARD_ORIGIN, config.BOARD_SIZE)
        previous_clip = surface.get_clip()
        surface.set_clip(viewport)
        surface.blit(self._sky(viewport), viewport.topleft)

        self.camera.prepare(viewport)
        self._draw_floor(surface, world)
        self._draw_walls(world)
        self._draw_food(world, elapsed)
        self._draw_snake(world, flash)
        self.face_count = self.batch.flush(surface)

        surface.set_clip(previous_clip)

    # ------------------------------------------------------------------ #
    def _sky(self, viewport: pygame.Rect) -> pygame.Surface:
        """Vertical gradient behind the board, cached per viewport size."""
        if self._sky_surface is not None and self._sky_surface.get_size() == viewport.size:
            return self._sky_surface

        sky = pygame.Surface(viewport.size)
        bands = 24
        band_height = max(1, viewport.height // bands + 1)
        for index in range(bands):
            t = index / max(1, bands - 1)
            color = _lerp_color(config.SKY_COLOR, config.HORIZON_COLOR, t)
            sky.fill(color, (0, index * band_height, viewport.width, band_height))
        self._sky_surface = sky
        return sky

    def _draw_floor(self, surface: pygame.Surface, world) -> None:
        """The ground plane and its grid, painted before every solid."""
        width, height = float(world.width), float(world.height)
        corners = [(0.0, 0.0, 0.0), (width, 0.0, 0.0), (width, 0.0, height), (0.0, 0.0, height)]
        self._fill_polygon(surface, corners, shade(config.FLOOR_COLOR, WORLD_UP))
        self._draw_grid_lines(surface, world)

    def _fill_polygon(
        self, surface: pygame.Surface, points: Sequence[Vec3], color: tuple[int, int, int]
    ) -> None:
        """Draw a world-space polygon immediately, clipped like batched faces."""
        camera = self.camera
        view = [camera.to_view(point) for point in points]
        if min(v[2] for v in view) < camera.near:
            view = clip_near(view, camera.near)
            if len(view) < 3:
                return
        screen = clip_to_rect([camera.project_view(v) for v in view], camera.viewport)
        if len(screen) >= 3:
            pygame.draw.polygon(surface, color, screen)

    def _draw_grid_lines(self, surface: pygame.Surface, world) -> None:
        color = config.FLOOR_GRID_COLOR
        width, height = float(world.width), float(world.height)
        for x in range(world.width + 1):
            self._line(surface, (x, 0.0, 0.0), (x, 0.0, height), color)
        for z in range(world.height + 1):
            self._line(surface, (0.0, 0.0, z), (width, 0.0, z), color)

    def _line(self, surface: pygame.Surface, a: Vec3, b: Vec3, color: tuple[int, int, int]) -> None:
        """Draw a world-space segment, clipped against the near plane."""
        camera = self.camera
        va, vb = camera.to_view(a), camera.to_view(b)
        if va[2] < camera.near and vb[2] < camera.near:
            return
        if va[2] < camera.near or vb[2] < camera.near:
            near, far = (va, vb) if va[2] < camera.near else (vb, va)
            t = (camera.near - near[2]) / (far[2] - near[2])
            clipped = (
                near[0] + (far[0] - near[0]) * t,
                near[1] + (far[1] - near[1]) * t,
                camera.near,
            )
            va, vb = (clipped, far) if va[2] < camera.near else (far, clipped)
        pygame.draw.line(surface, color, camera.project_view(va), camera.project_view(vb))

    def _draw_walls(self, world) -> None:
        """Four low ramparts marking the lethal border."""
        width, height = float(world.width), float(world.height)
        thickness, wall_height = 0.35, 0.75
        color = config.WALL_COLOR
        halves = (
            ((width / 2.0, wall_height / 2.0, -thickness / 2.0), width / 2.0 + thickness, thickness / 2.0),
            ((width / 2.0, wall_height / 2.0, height + thickness / 2.0), width / 2.0 + thickness, thickness / 2.0),
            ((-thickness / 2.0, wall_height / 2.0, height / 2.0), thickness / 2.0, height / 2.0 + thickness),
            ((width + thickness / 2.0, wall_height / 2.0, height / 2.0), thickness / 2.0, height / 2.0 + thickness),
        )
        for center, half_x, half_z in halves:
            self._add_box(center, half_x, wall_height / 2.0, half_z, color)

    def _add_box(
        self,
        center: Vec3,
        half_x: float,
        half_y: float,
        half_z: float,
        color: tuple[int, int, int],
    ) -> None:
        """Box with independent half-extents (walls are not cubes)."""
        x, y, z = center
        faces = (
            (((-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1)), (0, 1, 0)),
            (((-1, 1, 1), (1, 1, 1), (1, -1, 1), (-1, -1, 1)), (0, 0, 1)),
            (((1, 1, -1), (-1, 1, -1), (-1, -1, -1), (1, -1, -1)), (0, 0, -1)),
            (((1, 1, 1), (1, 1, -1), (1, -1, -1), (1, -1, 1)), (1, 0, 0)),
            (((-1, 1, -1), (-1, 1, 1), (-1, -1, 1), (-1, -1, -1)), (-1, 0, 0)),
        )
        for corners, normal in faces:
            points = [
                (x + cx * half_x, y + cy * half_y, z + cz * half_z) for cx, cy, cz in corners
            ]
            self.batch.add(points, normal, color)

    def _draw_food(self, world, elapsed: float) -> None:
        bob = 0.09 * math.sin(elapsed * 4.0)
        center = self.cell_center(world.food, 0.45 + bob)
        self.batch.add_cube(
            center,
            0.3,
            config.FOOD_COLOR,
            boost=0.25 + 0.2 * math.sin(elapsed * 6.0),
            yaw=elapsed * 1.6,
        )

    def _draw_snake(self, world, flash: float) -> None:
        length = world.length
        for index, segment in enumerate(world.snake):
            center = self.cell_center(segment, 0.4)
            if index == 0:
                self.batch.add_cube(center, 0.44, config.SNAKE_HEAD_COLOR, boost=flash * 0.5)
                self._draw_eyes(world, center)
            else:
                t = index / max(1, length - 1)
                color = _lerp_color(config.SNAKE_BODY_COLOR, config.SNAKE_TAIL_COLOR, t)
                self.batch.add_cube(center, 0.40 - 0.06 * t, color)

    def _draw_eyes(self, world, head_center: Vec3) -> None:
        forward = (float(world.direction.x), 0.0, float(world.direction.y))
        side = cross(forward, WORLD_UP)
        for sign in (-1.0, 1.0):
            center = add(
                add(head_center, scale(forward, 0.42)),
                add(scale(side, 0.2 * sign), (0.0, 0.16, 0.0)),
            )
            self.batch.add_cube(center, 0.1, config.EYE_COLOR, boost=0.4)


def _lerp_color(
    start: tuple[int, int, int], end: tuple[int, int, int], t: float
) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return (
        int(start[0] + (end[0] - start[0]) * t),
        int(start[1] + (end[1] - start[1]) * t),
        int(start[2] + (end[2] - start[2]) * t),
    )
