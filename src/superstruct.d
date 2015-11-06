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

/// SuperStruct forwards operators too:
unittest {
  import std.range, std.algorithm, std.container;

  alias Container(T) = SuperStruct!(SList!T, Array!T);

  Container!int slist = SList!int();

  // We can call any members that are common among containers
  slist.insert([1,2,3,4]);
  assert(slist.front == 1);

  // opSlice is supported on all the subtypes, but each returns a different type
  // Container.opSlice will return a SuperStruct of these types
  auto slice = slist[];     // [1,2,3,4]
  assert(slice.front == 1);
  slice.popFront();         // [2,3,4]
  assert(slice.front == 2);

  // as slice is a SuperStruct of range types, it still works as a range
  slist.insert(slice); // [2,3,4] ~ [1,2,3,4]
  assert(slist[].equal([2,3,4,1,2,3,4]));
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
 * `SuperStruct` ignores members beginning with "__" (double underscore).
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
  mixin(allVisitorCode!SubTypes);

  // - Basic Operator Forwarding ---------------------------------

  /// Operators are forwarded to the underlying type.
  auto opIndex(T...)(T t) { return _value.visitAny!(x => x[t]); }

  /// ditto
  auto opSlice()() { return _value.visitAny!(x => x[]); }

  /// ditto
  auto opSlice(A, B)(A a, B b) { return _value.visitAny!(x => x[a..b]); }

  /// ditto
  // TODO
  //auto opDollar()() { return _value.visitAny!(x => x.opDollar()); }

  /// ditto
  auto opUnary(string op)() { return _value.visitAny!(x => mixin(op~"x")); }

  /// ditto
  auto opBinary(string op, T)(T other) {
    return _value.visitAny!(x => mixin("x"~op~"other"));
  }

  /// ditto
  auto opOpAssign(string op, T)(T other) {
    return _value.visitAny!((ref x) => mixin("x"~op~"=other"));
  }

  /// ditto
  bool opEquals(T)(T other) {
    return _value.visitAny!(x => x == other);
  }

  // - Operator Forwarding between SuperStructs -----------------

  /**
   * Perform a binary operation between two superstructs.
   *
   * Only possible if such an operation is supported between any of the types
   * in either of the SuperStructs.
   */
  auto opBinary(string op, T : SuperStruct!V, V...)(T other) {
    return  _value.visitAny!(x =>
      other._value.visitAny!(y => mixin("x"~op~"y")));
  }

  /// ditto
  auto opOpAssign(string op, T : SuperStruct!V, V...)(T other) {
    return  _value.visitAny!((ref x) =>
      other._value.visitAny!((    y) => mixin("x"~op~"=y")));
  }

  /**
   * Compare one `SuperStruct` to another of the same type.
   *
   * Invokes opEquals if the contained types are comparable.
   * Otherwise returns false.
   */
  auto opEquals(typeof(this) other) {
    bool helper(A, B)(A a, B b) {
      static if (is(typeof(a == b)))
        return a == b;
      else
        return false;
    }

    return  _value.visitAny!(x =>
      other._value.visitAny!(y => helper(x, y)));
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

/// Operators get forwarded to the underlying type
unittest {
  struct Foo {
    auto opSlice() { return [1,2,3]; }
  }

  struct Bar {
    auto opSlice() { return [4,5,6]; }
  }

  SuperStruct!(Foo, Bar) fb = Foo();
  assert(fb[] == [1,2,3]);
}

/// SuperStructs of the same type can be compared:
unittest {
  struct A { int i; }
  struct B { int i; }
  struct C { int i; bool opEquals(T)(T other) { return other.i == i; } }

  SuperStruct!(A, B, C) a0 = A(0);
  SuperStruct!(A, B, C) a1 = A(1);
  SuperStruct!(A, B, C) b0 = B(0);
  SuperStruct!(A, B, C) c0 = C(0);

  assert(a0 == a0); // same type, same value
  assert(a0 != a1); // same type, different value
  assert(a0 != b0); // incomparable types return false
  assert(a0 == c0); // different but comparable types

  // SuperStructs with different sets of source types are not comparable, even
  // if the types they happen to contain at the moment are.
  SuperStruct!(A, B) different = A(0);
  static assert(!__traits(compiles, different == a0));
}

/// If members have common signatures but no common return type, the exposed
/// member returns a `SuperStruct` of the possible return types.
unittest {
  struct A { auto fun() { return 1; } }
  struct B { auto fun() { return "hi"; } }

  SuperStruct!(A, B) a = A();
  SuperStruct!(A, B) b = B();

  assert(a.fun == SuperStruct!(int, string)(1));
  assert(b.fun == SuperStruct!(int, string)("hi"));
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
template visitMember(string member, TemplateArgs...) {
  // if we got some explicit compile time args, we need to pass them along.
  // otherwise, omit the !() as an empty template arg list can cause issues
  static if (TemplateArgs.length)
    enum bang = "!(TemplateArgs)";
  else
    enum bang = "";

  // this nested function allows two sets of compile-time args:
  // one from the enclosing template scope and one for the variadic args of
  auto visitMember(V, Args...)(ref V var, Args args) {
    static if (Args.length == 0)      // field or 'getter' (no-args function)
      enum expression = "x."~member~bang;
    else static if (Args.length == 1) // field or 'setter' (1-arg function)
      enum expression = "x."~member~bang~"=args[0]";
    else                              // 2+ arg function
      enum expression = "x."~member~bang~"(args)";

    return var.visitAny!((ref x) => mixin(expression));
  }
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

  assert(visitMember!"num"(foo) == 4);
  assert(visitMember!"num"(bar) == 5);

  assert(visitMember!"num"(foo, 5) == 5);
  assert(visitMember!"num"(foo)    == 5);

  assert(visitMember!"shout"(foo) == "hi!");
  assert(visitMember!"shout"(bar) == "bye!");
  assert(visitMember!"shout"(bar) == "bye!");

  visitMember!"assign"(foo, 2);
  assert(visitMember!"num"(foo) == 2);

  visitMember!"assign"(bar, 2);
  assert(visitMember!"num"(bar) == 3); // bar adds 1

  visitMember!"assign"(foo, 2, 6);
  assert(visitMember!"num"(foo) == 8);

  visitMember!"set"(foo, 9);
  assert(visitMember!"num"(foo) == 9);

  // field 'othernum' only exists on bar
  static assert(!__traits(compiles, visitMember!"othernum"(bar)));
  static assert(!__traits(compiles, visitMember!"othernum"(bar)));

  // 3-param overload of 'assign' only exists on Bar
  static assert(!__traits(compiles, visitMember!"assign"(bar, 2, 6, 8)));
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

  assert(fb.visitMember!("noargs", add1)()        == 4); // 3 + 1
  assert(fb.visitMember!("onearg", add1)(5)       == 6); // 5 + 1
  assert(fb.visitMember!("twofns", add1, add2)(5) == 8); // 5 + 1 + 2

  // implicit type args
  assert(fb.visitMember!("onetype")(5)      == 8);   // 3 + 5
  assert(fb.visitMember!("twotype")(5, 7)   == 15);  // 3 + 5 + 7
  assert(fb.visitMember!("twotype")(5f, 7f) == 15f); // 3 + 5 + 7

  // explicit type args
  assert(fb.visitMember!("onetype", int)(5)             == 8);   // 3 + 5
  assert(fb.visitMember!("twotype", int)(5, 7)          == 15);  // 3 + 5 + 7
  assert(fb.visitMember!("twotype", float, float)(5, 7) == 15f); // 3 + 5 + 7

  // only specify some type args
  assert(fb.visitMember!("twotype", float)(5, 7) == 15f); // 3 + 5 + 7
}

auto visitAny(alias fn, V)(ref V var) {
  // Collect the possible return types for this function across the subtypes
  alias returnType(T) = typeof(fn(*var.peek!T));
  alias AllTypes      = staticMap!(returnType, V.AllowedTypes);

  enum allVoid   = EraseAll!(void, AllTypes).length == 0;
  enum allCommon = !is(CommonType!AllTypes == void);

  foreach(T ; var.AllowedTypes)
    if (auto ptr = var.peek!T) {
      static if (allCommon || allVoid)
        return fn(*ptr);
      else static if (!allVoid)
        return SuperStruct!AllTypes(fn(*ptr));
      else
        static assert(0, "Cannot mix void and non-void return types");
    }

  assert(0, "Variant holds no value");
}

unittest {
  struct Foo {
    auto opSlice() { return [1,2,3]; }
    auto opBinary(string op)(string val) { return "foo"~op~"val"; }
  }

  struct Bar {
    auto opSlice() { return [4,5,6]; }
    auto opBinary(string op)(string val) { return "foo"~op~"val"; }
  }

  Algebraic!(Foo, Bar) fb = Foo();
  assert(fb.visitAny!(x => x[]) == [1,2,3]);
}

unittest {
  struct One { auto opEquals(int i) { return i == 1; } }
  struct Two { auto opEquals(int i) { return i == 2; } }

  Algebraic!(One, Two) one = One();
  Algebraic!(One, Two) two = Two();

  assert( one.visitAny!(x => x == 1));
  assert(!one.visitAny!(x => x == 2));
  assert(!two.visitAny!(x => x == 1));
  assert( two.visitAny!(x => x == 2));
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
    template %s(TemplateArgs...) {
      auto %s(Args...)(Args args) {
        return visitMember!("%s", TemplateArgs)(_value, args);
      }
    }
  }.format(name, name, name);
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
  // allMembers will fail on a primitive types, so alias that to an empty list
  template allMembers(T) {
    static if (__traits(compiles, __traits(allMembers, T)))
      alias allMembers = AliasSeq!(__traits(allMembers, T));
    else
      alias allMembers = AliasSeq!();
  }

  // ignore hidden members like __ctor, this, and operators
  enum shouldExpose(string name) = (name.length < 2 || name[0..2] != "__") &&
                                   name != "this"     &&
                                   name != "opUnary"  &&
                                   name != "opBinary" &&
                                   name != "opCast"   &&
                                   name != "opEquals" &&
                                   name != "opCmp"    &&
                                   name != "opCall"   &&
                                   name != "opAssign" &&
                                   name != "opIndex"  &&
                                   name != "opSlice"  &&
                                   name != "opDollar";

  string str;

  // generate a member to forward to each underlying member
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
  static assert( is(typeof(fb.d()) == SuperStruct!(int, string)));
  static assert(!is(typeof(fb.e())));  // setter only

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
