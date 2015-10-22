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
  Shape someShape = Circle(4, 0, 0);
  someShape.top = 6;
  assert(someShape.top == 6);

  // if a Shape is a Square, `top` forwards to Squares's top field
  someShape = Square(0, 0, 4, 4);
  someShape.top = 6;
  assert(someShape.top == 6);

  // Square.left is hidden, as Circle has no such member
  static assert(!is(typeof(someShape.left)));
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

  auto opAssign(V)(V value) if (is(typeof(_value = value))) {
    return _value = value;
  }

  /// Forward all members and template instantiations to the contained value.
  template opDispatch(string op) {
    template opDispatch(TemplateArgs...) {
      auto opDispatch(Args...)(Args args) {
        return visitor!(op, TemplateArgs)(_value, args);
      }
    }
  }
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

/// Templated members can be forwarded too:
unittest {
  struct Foo {
    int val;
    auto transmorgrify(alias fn1, alias fn2)() {
      return fn2(fn2(val));
    }
  }

  struct Bar {
    auto transmorgrify(alias fn1, alias fn2)() { return 0; }
  }

  static auto add1 = (int a) => a + 1;

  alias FooBar = SuperStruct!(Foo, Bar);

  FooBar f = Foo(3);
  assert(f.transmorgrify!(add1, add1) == 5); // 3 + 1 + 1

  FooBar b = Bar();
  assert(b.transmorgrify!(add1, add1) == 0);
}

/**
 * Wrap one of several values in a `SuperStruct`.
 *
 * This can be used to return a value from one of several different types.
 * Similar to `std.range.chooseAmong`, but for a broader range of types.
 *
 * Returns: A `SuperStruct!T` constructed from the value at `index`.
 */
auto pick(T...)(size_t index, T values) {
  foreach(idx, val ; values)
    if (idx == index)
      return SuperStruct!T(val);

  assert(0, "index not in range of provided values");
}

/// `pick` is useful for something that is a floor wax _and_ a dessert topping:
unittest {
  struct FloorWax       { string itIs() { return "a floor wax!";       } }
  struct DessertTopping { string itIs() { return "a dessert topping!"; } }

  auto shimmer(bool hungry) {
    return pick(hungry, FloorWax(), DessertTopping());
  }

  assert(shimmer(false).itIs == "a floor wax!");
  assert(shimmer(true ).itIs == "a dessert topping!");
}

private:
/*
 * Try to invoke `member` with the provided `args` for every `AllowedType`.
 * Compiles only if such a call is possible on every type.
 * Compiles only if the return values of all such calls share a common type.
 */
template visitor(string member, TemplateArgs...) {
  // if we got some explicit compile time args, we need to pass them along.
  // otherwise, omit the !() as an empty template arg list can cause issues
  static if (TemplateArgs.length)
    enum bang = "!(TemplateArgs)";
  else
    enum bang = "";

  auto helper(V, Args...)(ref V var, Args args) {
    static if (Args.length == 0)      // field or 'getter' (no-args function)
      enum expression = "ptr."~member~bang;
    else static if (Args.length == 1) // field or 'setter' (1-arg function)
      enum expression = "ptr."~member~bang~"=args[0]";
    else                              // 2+ arg function
      enum expression = "ptr."~member~bang~"(args)";

    foreach(T ; var.AllowedTypes)
      if (auto ptr = var.peek!T)
        return mixin(expression);

    assert(0, "Variant holds no value");
  }

  alias visitor = helper;
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

// pass along template arguments
unittest {
  struct Foo {
    int val;

    auto noargs(alias fn)() { return fn(val); }
    auto onearg(alias fn)(int i) { return fn(i);   }
    auto twofns(alias fn1, alias fn2)(int i) { return fn2(fn1(i)); }

    auto onetype(T)(T arg) { return val + arg; }
    auto twotype(T, V)(T t, V v) { return val + t + v; }
  }

  struct Bar {
    int val;

    auto noargs(alias fn)() { return fn(val); }
    auto onearg(alias fn)(int i) { return fn(i);   }
    auto twofns(alias fn1, alias fn2)(int i) { return fn2(fn1(i)); }

    auto onetype(T)(T arg) { return val + arg; }
    auto twotype(T, V)(T t, V v) { return val + t + v; }
  }

  alias FooBar = Algebraic!(Foo, Bar);
  FooBar fb = Foo(3);

  // need to use a static fn here due to unrelated issue:
  // cannot use local 'add1' as parameter to non-global template
  static auto add1 = (int a) => a + 1;
  static auto add2 = (int a) => a + 2;

  assert(fb.visitor!("noargs", add1)()        == 4); // 3 + 1
  assert(fb.visitor!("onearg", add1)(5)       == 6); // 5 + 1
  assert(fb.visitor!("twofns", add1, add2)(5) == 8); // 5 + 1 + 2

  // implicit type args
  assert(fb.visitor!("onetype")(5)      == 8);   // 3 + 5
  assert(fb.visitor!("twotype")(5, 7)   == 15);  // 3 + 5 + 7
  assert(fb.visitor!("twotype")(5f, 7f) == 15f); // 3 + 5 + 7

  // explicit type args
  assert(fb.visitor!("onetype", int)(5)             == 8);   // 3 + 5
  assert(fb.visitor!("twotype", int)(5, 7)          == 15);  // 3 + 5 + 7
  assert(fb.visitor!("twotype", float, float)(5, 7) == 15f); // 3 + 5 + 7

  // only specify some type args
  assert(fb.visitor!("twotype", float)(5, 7) == 15f); // 3 + 5 + 7
}
