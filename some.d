module some;

import std.meta;
import std.traits;
import std.variant;

auto visitAny(alias fn, V)(ref V var) {
  foreach(T ; V.AllowedTypes)
    if (auto ptr = var.peek!T) return fn(*ptr);

  assert(0, "No matching type!");
}

private string accessor(T, string name)() {
  import std.string : format;
  auto getter =
    "auto %s() { return _value.visitAny!(x => x.%s); }"
    .format(name, name);

  auto setter =
    "auto %s(V)(V val)
     if (is(typeof(_value.visitAny!(x => x.%s = val))))
     {
       return _value.visitAny!((ref x) => x.%s = val);
     }"
    .format(name, name, name);

  return getter ~ setter;
}

template hasField(T, FieldType, string name) {
  enum hasField = staticIndexOf!(name, FieldNameTuple!T) >= 0;
}

private string commonFieldAccessors(T...)() {
  string str;
  foreach(i, FieldName ; FieldNameTuple!(T[0])) {
    alias FieldType = FieldTypeTuple!(T[0])[i];

    static if (hasField!(T[1], FieldType, FieldName))
      str ~= accessor!(FieldType, FieldName);
  }

  return str;
}

struct Some(T...) {
  Algebraic!T _value;

  this(V)(V value) if (is(typeof(_value = value))) {
    _value = value;
  }

  mixin(commonFieldAccessors!T);

  auto opDispatch(string op, Args...)(Args args) {
    return _value.visitAny!((ref x) => mixin("x." ~ op ~ "(args)"));
  }
}

unittest {
  import std.math, std.algorithm;

  struct Color { float r, g, b; }

  struct Square {
    float x, y, size;
    Color color;

    float area() { return size * size; }
    float perimeter() { return 4 * size; }
  }

  struct Circle {
    float x, y, r;
    Color color;

    float area() { return r * r * PI; }
    float perimeter() { return 2 * PI * r; }
  }

  alias Shape = Some!(Square, Circle);

  Shape sqr = Square(1,2,3);
  Shape cir = Circle(0,0,4);
  Shape[] shapes = [ sqr, cir ];
  assert(shapes.map!(x => x.area).sum.approxEqual(3 * 3 + 4 * 4 * PI));

  sqr.color = Color(1,0,0);
  assert(sqr.color.r == 1);
}
