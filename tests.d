import superstruct;

import std.math;
import std.traits;

struct Vector2(T : real) {
  T x, y;

  auto len() { return sqrt(x * x + y * y); }

  auto opBinary(string op)(Vector2!T other) {
    return Vector2!T(mixin("x"~op~"other.x"),
                     mixin("y"~op~"other.y"));
  }

  auto opBinary(string op)(T arg) {
    return Vector2!T(mixin("x"~op~"arg"),
                     mixin("y"~op~"arg"));
  }
}

bool approxEqual(T : real)(T lhs, T rhs) {
 return std.math.approxEqual(lhs, rhs);
}

bool approxEqual(T : real)(Vector2!T lhs, Vector2!T rhs) {
  return approxEqual(lhs.x, rhs.x) &&
         approxEqual(lhs.y, rhs.y);
}

struct Rect(T : real) {
  Vector2!T topLeft, size;

  auto center()              { return topLeft + size / 2; }
  auto center(Vector2!T val) { return topLeft = val - size / 2; }

  auto area() { return size.x * size.y; }
}

struct Ellipse(T : real) {
  Vector2!T center, radius;

  auto topLeft()              { return center - radius; }
  auto topLeft(Vector2!T val) { return center = val + radius; }

  auto area() { return radius.x * radius.y * PI; }
}

alias Shape(T : real) = SuperStruct!(Rect!T, Ellipse!T);

static assert( hasMember!(Shape!float, "center"));
static assert( hasMember!(Shape!float, "topLeft"));
static assert( hasMember!(Shape!float, "area"));

// for now, size and radius are generated as templated setters.
// their constraints are such that they cannot instantiate, but in the long run
// they should not be generated at all.
// static assert( hasMember!(Shape!float, "size"));   // only on Rect
// static assert( hasMember!(Shape!float, "radius")); // only on ellipse

unittest {
  alias Vector2f = Vector2!float;

  Shape!float r = Rect!float(Vector2f(0, 0), Vector2f(16, 16));

  assert(approxEqual(r.topLeft, Vector2f(0, 0)));
  assert(approxEqual(r.center , Vector2f(8, 8)));
  assert(approxEqual(r.area   , 256));

  Shape!float e = Ellipse!float(Vector2f(0, 0), Vector2f(16, 16));

  assert(approxEqual(e.center , Vector2f(0, 0)));
  assert(approxEqual(e.topLeft, Vector2f(-16, -16)));
  assert(approxEqual(e.area   , 16 * 16 * PI));

  static assert(!__traits(compiles, { r.size;   })); // no size on Ellipse
  static assert(!__traits(compiles, { r.radius; })); // no radius on Rect
}
