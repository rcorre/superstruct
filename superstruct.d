module superstruct;

import std.meta;
import std.traits;
import std.variant;

struct SuperStruct(SubTypes...) {
  Algebraic!SubTypes _value;

  this(V)(V value) if (is(typeof(_value = value))) {
    _value = value;
  }

  mixin(commonAccessors!SubTypes);

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

  alias Shape = SuperStruct!(Square, Circle);

  Shape sqr = Square(1,2,3);
  Shape cir = Circle(0,0,4);
  Shape[] shapes = [ sqr, cir ];
  assert(shapes.map!(x => x.area).sum.approxEqual(3 * 3 + 4 * 4 * PI));

  sqr.color = Color(1,0,0);
  assert(sqr.color.r == 1);
}

private:
auto varGet(string name, V)(V var) {
  foreach(SubType ; V.AllowedTypes)
    if (auto ptr = var.peek!SubType)
      return mixin("(*ptr)." ~ name);

  assert(0);
}

auto varSet(string name, SuperType, ArgType)(ref SuperType var, ArgType value) {
  foreach(SubType ; SuperType.AllowedTypes)
    if (auto ptr = var.peek!SubType)
      return mixin("(*ptr)." ~ name ~ "=value");

  assert(0);
}

auto varCall(string name, V, Args...)(ref V var, Args args) {
  foreach(SubType ; V.AllowedTypes)
    if (auto ptr = var.peek!SubType)
      return mixin("(*ptr)." ~ name ~ "(args)");

  assert(0);
}

unittest {
  struct Foo {
    int num;

    string shout() { return "hi!"; }
    void assign(int val) { num = val; }
    void assign(int val1, int val2) { num = val1 + val2; }
  }

  struct Bar {
    int num, othernum;

    string shout() { return "bye!"; }
    void assign(int val) { num = val + 1; }
    void assign(int val1, int val2) { num = val1 + val2 + 1; }
    void assign(int val1, int val2, int val3) { num = val1 + val2 + val3; }
  }

  alias Thing = Algebraic!(Foo, Bar);

  Thing foo = Foo(4);
  Thing bar = Bar(5, 6);

  assert(varGet!"num"(foo) == 4);
  assert(varGet!"num"(bar) == 5);

  assert(varSet!"num"(foo, 5) == 5);
  assert(varGet!"num"(foo) == 5);

  assert(varCall!"shout"(foo) == "hi!");
  assert(varCall!"shout"(bar) == "bye!");
  assert(varCall!"shout"(bar) == "bye!");

  varCall!"assign"(foo, 2);
  assert(varGet!"num"(foo) == 2);

  varCall!"assign"(bar, 2);
  assert(varGet!"num"(bar) == 3); // bar adds 1

  varCall!"assign"(foo, 2, 6);
  assert(varGet!"num"(foo) == 8);

  // field 'othernum' only exists on bar
  static assert(!__traits(compiles, varGet!"othernum"(bar)));
  static assert(!__traits(compiles, varSet!"othernum"(bar)));

  // 3-param overload of 'assign' only exists on Bar
  static assert(!__traits(compiles, varCall!"assign"(bar, 2, 6, 8)));
}

// true if "name" is a field or 0-arg method of every AllowedType,
// and all such fields/members have compatible return types
enum canGet(string name, V) = is(typeof(varGet!name(V.init)));

// TODO:
// true if "name" is a method callable with Args
//enum canCall(string name, V, R, Args...) = is(typeof(varCall!name(V.init, Args.init)));

unittest {
  struct Foo {
    int   a;
    float b;
    int   c;
    int   d;
    int   e;
    int   f;
  }

  struct Bar {
    int a;
    int b;
    // no c
    int d() { return _d; }
    int e() { return _e; }
    int e(int val) { return _e = val; }
    ref int f() { return _f; }

    int _d, _e, _f;
  }

  alias Thing = Algebraic!(Foo, Bar);

  static assert( canGet!("a", Thing)); // field of same type
  static assert( canGet!("b", Thing)); // field of differing type, can upcast
  static assert(!canGet!("c", Thing)); // field does not exist on all types
  static assert( canGet!("d", Thing)); // field on one, getter property on the other
  static assert( canGet!("e", Thing)); // field on one, getter/setter property on the other
  static assert( canGet!("f", Thing)); // field on one, ref property on the other
}

auto visitAny(alias fn, V)(ref V var) {
  foreach(T ; V.AllowedTypes)
    if (auto ptr = var.peek!T) return fn(*ptr);

  assert(0, "No matching type!");
}

/* This generates a property that gets the member across any of the source types.
 * The return type will be the common type across that member on all source types.
 * For example, if the member is a float field on one source type and an int on another,
 * the return type will be a float.
 */
string getterCode(string member)() {
  import std.string : format;

  return q{
    @property auto %s()
    {
      return _value.varGet!"%s";
    }
  }.format(member, member);
}

unittest {
  struct Foo {
    int a;
    int b;
    int c;
    int d;
    int e;
  }

  struct Bar {
    int    a;
    real   b;
    int    c() { return 1; }        // getter only
    string d;                       // incompatible type
    int    e(int val) { return 0; } // setter only
  }

  struct FooBar {
    alias Store = Algebraic!(Foo, Bar);
    Store _value;

    mixin(getterCode!("a"));
    mixin(getterCode!("b"));
    mixin(getterCode!("c"));
  }

  FooBar fb;

  static assert(is(typeof(fb.a()) == int));  // both are int
  static assert(is(typeof(fb.b()) == real)); // real is common type of (int, real)
  static assert(is(typeof(fb.c()) == int));  // field on Foo, function on Bar
}

/* This generates a property that sets the member across any of the source types.
 * The return type will be the common type across that member on all source types.
 * We cannot determine a concrete type for the argument, as it could be a templated function in one
 * of the source types.
 * Therefor, this property si a template function constrained to values that can be used to set the
 * matching member on each of the underlying source types. For example, if the member "m" is a
 * float field on one source type and an int field on the other, this property will accept an int
 * (which is implicitly convertible to float) but not a float (as it is not implicitly convertible
 * to int).
 */
string setterCode(string member)() {
  import std.string : format;
  return q{
    auto %s(ArgType)(ArgType arg) if (is(typeof(_value.varSet!"%s"(arg))))
    {
      return _value.varSet!"%s"(arg);
    }
  }.format(member, member, member);
}

unittest {
  struct Foo {
    int a;
    int b;
    int c;
    int d;
    int e;
  }

  struct Bar {
    int    a;
    real   b;
    int    c() { return 1; }        // getter only
    string d;                       // incompatible type
    int    e(int val) { return 0; } // setter only
  }

  struct FooBar {
    alias Store = Algebraic!(Foo, Bar);
    Store _value;

    this(T)(T t) { _value = t; }

    mixin(setterCode!("a"));
    mixin(setterCode!("b"));
    mixin(setterCode!("c"));
    mixin(setterCode!("d"));
    mixin(setterCode!("e"));
  }

  FooBar fb = Foo(1);

  static assert( is(typeof(fb.a = 5) == int )); // both are int
  static assert( is(typeof(fb.b = 5) == real)); // real is common type of (int, real)
  static assert( is(typeof(fb.e = 5) == int )); // field on Foo, function on Bar

  static assert(!is(typeof(fb.b = 5.0))); // type mismatch
  static assert(!is(typeof(fb.c = 5  ))); // getter only
  static assert(!is(typeof(fb.d = 5  ))); // incompatible types
  static assert(!is(typeof(fb.d = 5.0))); // incompatible types
}

// Generate a set of setters and getters for the common fields/members across all SubTypes.
string commonAccessors(SubTypes...)() {
  alias SuperType = Algebraic!SubTypes;
  enum allMembers(T) = __traits(allMembers, T);

  string str;

  foreach(member ; NoDuplicates!(staticMap!(allMembers, SubTypes))) {
    // The getter is not templated, so we should only include it if it is viable.
    // Fortunately, we can tell this ahead of time based on the return types of the SubType getters.
    static if (canGet!(member, SuperType))
        str ~= getterCode!(member);

    // We cannot tell ahead of time whether we can generate a viable setter.
    // Instead we generate a setter that takes a generic arg, and determines whether it is viable
    // for any particular call.
    // It is possible to generate a setter with an impossible-to-satisfy template constraint.
    // This shouldn't be a problem.
    str ~= setterCode!(member);
  }

  return str;
}

unittest {
  struct Foo {
    int a;
    int b;
    int c;
    int d;
    int e;
  }

  struct Bar {
    int    a;
    real   b;
    int    c() { return 1; }        // getter only
    string d;                       // incompatible type
    int    e(int val) { return 0; } // setter only
  }

  struct FooBar {
    alias Store = Algebraic!(Foo, Bar);
    Store _value;

    this(T)(T t) { _value = t; }

    mixin(commonAccessors!(Foo, Bar));
  }

  FooBar fb = Foo(1);

  // getters
  static assert( is(typeof(fb.a()) == int));  // both are int
  static assert( is(typeof(fb.b()) == real)); // real is common type of (int, real)
  static assert( is(typeof(fb.c()) == int));  // field on Foo, function on Bar
  static assert(!is(typeof(fb.d())       ));  // no common type between (int, string)
  static assert(!is(typeof(fb.e())       ));  // setter only

  // setters
  static assert( is(typeof(fb.a = 5) == int )); // both are int
  static assert( is(typeof(fb.b = 5) == real)); // real is common type of (int, real)
  static assert( is(typeof(fb.e = 5) == int )); // field on Foo, function on Bar

  static assert(!is(typeof(fb.b = 5.0))); // type mismatch
  static assert(!is(typeof(fb.c = 5  ))); // getter only
  static assert(!is(typeof(fb.d = 5  ))); // incompatible types
  static assert(!is(typeof(fb.d = 5.0))); // incompatible types
}
