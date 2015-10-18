/**
 * This module provides a single type, `SuperStruct`.
 *
 * Authors: Ryan Roden-Corrent ($(LINK2 https://github.com/rcorre, rcorre))
 * License: MIT
 * Copyright: © 2015, Ryan Roden-Corrent
 */
module superstruct;

/// Two disparate structs ... they can't be used interchangeably, right?
unittest {
  import std.math, std.algorithm;

  struct Square {
    float size;
    float area() { return size * size; }
  }

  struct Circle {
    float r;
    float area() { return r * r * PI; }
  }

  // Or can they?
  alias Shape = SuperStruct!(Square, Circle);

  // look! polymorphism!
  Shape sqr = Square(2);
  Shape cir = Circle(4);
  Shape[] shapes = [ sqr, cir ];

  // call functions that are shared between the source types!
  assert(shapes.map!(x => x.area).sum.approxEqual(2 * 2 + 4 * 4 * PI));
}

/// Want to access fields of the underlying types? Not a problem!
/// Are some of them properties? Not a problem!
unittest {
  struct Square {
    int top, left, width, height;
  }

  struct Circle {
    int radius;
    int x, y;

    auto top() { return y - radius; }
    auto top(int val) { return y = val + radius; }
  }

  alias Shape = SuperStruct!(Square, Circle);

  // if a Shape is a Circle, `top` forwards to Circle's top property
  Shape cir = Circle(4, 0, 0);
  assert(cir.top = 6);
  assert(cir.top == 6);

  // if a Shape is a Square, `top` forwards to Squares's top field
  Shape sqr = Square(0, 0, 4, 4);
  assert(sqr.top = 6);
  assert(sqr.top == 6);

  // Square.left is hidden, as Circle has no such member
  static assert(!is(typeof(sqr.left)));
}

import std.meta;
import std.traits;
import std.variant;

/** A Variant which exposes members that are common across all `SubTypes`.
 *
 * A `SuperStruct!(SubTypes...)` wraps an `Algebraic!(SubTypes...)`.  It can
 * hold a single value from any of its `SubTypes`.
 *
 * Unlike a Variant/Algebraic, `SuperStruct` exposes access to 'common' members
 * that have compatible signatures.
 *
 * A member is 'common' if its name describes a public function or field on
 * every one of `SubTypes`. A call signature for a given member is 'compatible'
 * if, for an instance of any one of `SubTypes`, that member can be called with
 * the provided set of arguments _and_ all such calls have a common return type.
 *
 * `SuperStruct` ignores members beginning with "__".
 */
struct SuperStruct(SubTypes...) {
  private Algebraic!SubTypes _value;

  /**
   * Construct and populate with an initial value.
   * Params:
   *   value = something implicitly covertible to of one of the `SubTypes`.
   */
  this(V)(V value) if (is(typeof(_value = value))) {
    _value = value;
  }

  // the meta-magic for exposing common members
  mixin(allVisitorCode!SubTypes);
}

/// If all types have a matching field, it gets exposed:
unittest {
  struct Foo { int a; }
  struct Bar { int a; }
  auto foobar = SuperStruct!(Foo, Bar)(Foo(1));
  foobar.a = 5;
  assert(foobar.a == 5);
}

/// If all types have a matching method, all compatible overloads are exposed:
unittest {
  struct Foo {
    int fun(int i) { return i; }
    int fun(int a, int b) { return a + b; }
  }
  struct Bar {
    int fun(int i) { return i; }
    int fun(int a, int b) { return a + b; }
    int fun(int a, int b, int c) { return a + b + c; }
  }

  auto foobar = SuperStruct!(Foo, Bar)(Foo());
  assert(foobar.fun(1)    == 1);
  assert(foobar.fun(1, 2) == 3);
  assert(!__traits(compiles, foobar.fun(1,2,3))); // no such overload on Foo
}

/// If a name is a field on one type and a method on another, it is exposed:
unittest {
  struct Foo { int a; }
  struct Bar {
    private int _a;
    int a() { return _a; }
    int a(int val) { return _a = val; }
  }

  auto foo = SuperStruct!(Foo, Bar)(Foo());
  foo.a = 5;          // sets Foo.a
  assert(foo.a == 5); // gets Foo.a

  auto bar = SuperStruct!(Foo, Bar)(Bar());
  bar.a = 5;          // invokes Bar.a(int val)
  assert(bar.a == 5); // invokes Bar.a()
}

private:
/*
 * Try to invoke `member` with the provided `args` for every `AllowedType`.
 * Compiles only if such a call is possible on every type.
 * Compiles only if the return values of all such calls share a common type.
 */
auto visitor(string member, V, Args...)(ref V var, Args args) {
  static if (Args.length == 0)      // field or 'getter' (no-args function)
    enum expression = "ptr."~member;
  else static if (Args.length == 1) // field or 'setter' (1-arg function)
    enum expression = "ptr."~member~"=args[0]";
  else                              // 2+ arg function
    enum expression = "ptr."~member~"(args)";

  foreach(T ; var.AllowedTypes)
    if (auto ptr = var.peek!T)
      return mixin(expression);

  assert(0, "Variant holds no value");
}

unittest {
  struct Foo {
    int num;

    string shout() { return "hi!"; }
    void assign(int val) { num = val; }
    void assign(int val1, int val2) { num = val1 + val2; }

    void set(T)(T val) { num = val; } // templated setter
  }

  struct Bar {
    int num, othernum;

    string shout() { return "bye!"; }
    void assign(int val) { num = val + 1; }
    void assign(int val1, int val2) { num = val1 + val2 + 1; }
    void assign(int val1, int val2, int val3) { num = val1 + val2 + val3; }

    void set(T)(T val) { num = val; }
  }

  alias Thing = Algebraic!(Foo, Bar);

  Thing foo = Foo(4);
  Thing bar = Bar(5, 6);

  assert(visitor!"num"(foo) == 4);
  assert(visitor!"num"(bar) == 5);

  assert(visitor!"num"(foo, 5) == 5);
  assert(visitor!"num"(foo)    == 5);

  assert(visitor!"shout"(foo) == "hi!");
  assert(visitor!"shout"(bar) == "bye!");
  assert(visitor!"shout"(bar) == "bye!");

  visitor!"assign"(foo, 2);
  assert(visitor!"num"(foo) == 2);

  visitor!"assign"(bar, 2);
  assert(visitor!"num"(bar) == 3); // bar adds 1

  visitor!"assign"(foo, 2, 6);
  assert(visitor!"num"(foo) == 8);

  visitor!"set"(foo, 9);
  assert(visitor!"num"(foo) == 9);

  // field 'othernum' only exists on bar
  static assert(!__traits(compiles, visitor!"othernum"(bar)));
  static assert(!__traits(compiles, visitor!"othernum"(bar)));

  // 3-param overload of 'assign' only exists on Bar
  static assert(!__traits(compiles, visitor!"assign"(bar, 2, 6, 8)));
}

/*
 * Generate a templated function to expose access to a given member across all
 * types that could be stored in the Variant `_value`.
 * For any given call signature, this template will instantiate only if the
 * matching member on every subtype is callable with such a signature _and_ if
 * all such calls have a common return type.
 */
string memberVisitorCode(string name)() {
  import std.string : format;

  return q{
    auto %s(Args...)(Args args) {
      return visitor!"%s"(_value, args);
    }
  }.format(name, name);
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

    mixin(memberVisitorCode!("a"));
    mixin(memberVisitorCode!("b"));
    mixin(memberVisitorCode!("c"));
    mixin(memberVisitorCode!("d"));
    mixin(memberVisitorCode!("e"));
  }

  FooBar fb = Foo(1);

  static assert(is(typeof(fb.a()) == int));  // both are int
  static assert(is(typeof(fb.b()) == real)); // real is common type of (int, real)
  static assert(is(typeof(fb.c()) == int));  // field on Foo, function on Bar

  static assert( is(typeof(fb.a = 5) == int )); // both are int
  static assert( is(typeof(fb.b = 5) == real)); // real is common type of (int, real)
  static assert( is(typeof(fb.e = 5) == int )); // field on Foo, function on Bar

  static assert(!is(typeof(fb.b = 5.0))); // type mismatch
  static assert(!is(typeof(fb.c = 5  ))); // getter only
  static assert(!is(typeof(fb.d = 5  ))); // incompatible types
  static assert(!is(typeof(fb.d = 5.0))); // incompatible types
}

/*
 * Generate a string containing the `memberVisitorCode` for every name in the
 * union of all members across SubTypes.
 */
string allVisitorCode(SubTypes...)() {
  enum allMembers(T) = __traits(allMembers, T);

  // ignore __ctor, __dtor, and the like
  enum shouldExpose(string name) = name.length < 2 || name[0..2] != "__";

  string str;

  foreach(member ; NoDuplicates!(staticMap!(allMembers, SubTypes)))
    static if (shouldExpose!member)
      str ~= memberVisitorCode!(member);

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

    mixin(allVisitorCode!(Foo, Bar));
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

// make sure __ctor and __dtor don't blow things up
unittest {
  struct Foo {
    this(int i) { }
    this(this) { }
    ~this() { }
  }

  struct Bar {
    this(int i) { }
    this(this) { }
    ~this() { }
  }

  struct FooBar {
    alias Store = Algebraic!(Foo, Bar);
    Store _value;

    this(T)(T t) { _value = t; }

    mixin(allVisitorCode!(Foo, Bar));
  }

  FooBar fb = Foo(1);
}
