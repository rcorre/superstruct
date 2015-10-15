SuperStruct
===

[(docs)](http://rcorre.github.io/superstruct).

[(dub)](http://code.dlang.org/packages/superstruct).

# What is it?

It's a `struct`! It's a `class`! No, its ...

`SuperStruct`!

Lighter than a `class` and classier than a `struct`, `SuperClass` is the bastard
child of
[`wrap`](http://dlang.org/phobos/std_typecons.html#.wrap) and
[`variant`](http://dlang.org/phobos/std_variant.html).

Example time!

```d
// two disparate structs ... they can't be used interchangeably, right?
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
assert(shapes.map!(x => x.area).sum.approxEqual(3 * 3 + 4 * 4 * PI));
```

Want to access fields of the underlying types? Not a problem!
Are some of them properties? Not a problem!

```d
struct Square {
  Vector2f topLeft, size;
  auto center() { return topLeft + size / 2; }
  auto center(Vector2f val) { return topLeft = val - size / 2; }
}

struct Circle {
  float r;
  Vector2f center;
}

alias Shape = SuperStruct!(Square, Circle);

Shape sqr = Square(Vector2f(0,0), Vector2f(4,4));
Shape cir = Circle(4, Vector2f(8,8));

// we can get/set center as it is a field on Circle and a property on Square
// if Square.center had no setter, then we would only be able to get
sqr.center = cir.center;

// Square.topLeft is hidden, as Circle has no such member
static assert(!is(typeof(sqr.topLeft)));
```

# Is it useful?

I don't know, you tell me. I just work here.

If nothing else, its an interesting exercise in what D's compile-time facilities
are capable of.

## Why not use Variant/Algebraic?

To avoid repeating yourself.

```d

// Compare this...
auto alg = Algebraic!(Rect, Ellipse, Triangle)(someShape); // or a variant
auto center1 = alg.visit!((Rect r)     => r.center,
                          (Ellipse e)  => e.center,
                          (Triangle t) => t.center)

// To this! Easier, right?
auto center2 = sup.center;
```

## Why not use wrap?

1. `wrap` does not _currently_ support structs (but a PR exists to implement this)
2. `wrap` allocates a class. `SuperStruct` is just a struct.
3. `wrap` requires an explicitly defined interface. `SuperStruct` generates an
   interface automatically.

# How does it work?
Given a set of 'sub types', `SuperStruct` automatically generates a 'super
type' consisting of the common members.

Given the structs `Foo` and `Bar`:

```d
struct Foo {
  int    a;
  string b;
  real   x;
  float  fun(int i, string s) { }
  int    meh(int i) { }
}

struct Bar {
  int    a;
  string b() { }
  real   y;
  int    fun(int i, string s) { }
  int    meh(float f) { }
}
```

You can think of `SuperStruct!(Foo, Bar)` as:

```d
struct FooBar {
  int    a() { }
  int    a(int arg) { }
  string b() { }
  int    fun(int i, string s) { }
  float  fun(float f) { }
  int    meh(int f) { }
}
```

- `a` is an int field on both `Foo` and `Bar`, so it is exposed.
- `b` is a field on `Foo`, but only a getter on `Bar`, so we only expose the getter.
- `fun` is has a common signature on both `Foo` and `Bar`, so it is exposed.
  However, note that `Foo.fun` returns a float and `Bar.fun` returns an `int`.
  The exposed `fun` returns the `CommonType`, which is `int`.
- `meh` is exposed, but only accepts an `int` as a parameter.
  While `Bar.meh` could accept a float, `Foo.meh` cannot (implicitly) do so.

# How does it REALLY work?
That example I showed you of the generated struct for `SuperStruct!(Foo,Bar)`?
That was a lie. You can _think_ of it looking like that to picture the interface
it exposes, but it _actually_ looks more like this:

```d
struct FooBar {
  private Algebraic!(Foo,Bar) _value;

  auto a(Args...)(Args args) if (is(typeof(_value.visitor!"a"(args)))) { }
  auto b(Args...)(Args args) if (is(typeof(_value.visitor!"b"(args)))) { }
  // and so on ...
}
```

Where `visitor` is a little helper that tries to forward the call to whatever
`_value` is holding.