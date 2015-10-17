SuperStruct
===

- [code](http://github.com/rcorre/superstruct).
- [docs](http://rcorre.github.io/superstruct).
- [dub](http://code.dlang.org/packages/superstruct).

Let's say you've got a few structs representing shapes, say, `Circle`, `Square`
and `Triangle`. You want an overarching type to store any one of these shapes.

```d
alias Shape = Algebraic!(Circle, Square, Triangle)
Shape shape = Circle(x, y, radius);
```

Ok, an `Algebraic` (or `Variant`, in general) isn't a bad choice. Now, could you 
grab the `area` of that shape for me?

```d
auto area = shape.visit!((Circle c)   => c.area,
                         (Square s)   => s.area,
                         (Triangle t) => t.area);
```

Alright, that works well enough. How about the `perimeter`? They all have one of
those, don't they?

```d
auto perimeter = shape.visit!((Circle c)   => c.perimeter,
                              (Square s)   => s.perimeter,
                              (Triangle t) => t.perimeter);
```

At this point, you may be wondering if there's a better way.

# What is it?

It's a `struct`! It's a `class`! No, its ...  `SuperStruct`!

This bastard child of
[`wrap`](http://dlang.org/phobos/std_typecons.html#.wrap) and
[`variant`](http://dlang.org/phobos/std_variant.html)
works like an `Algebraic`, but allows access to members that are common across
the source types.

```d
struct Square {
  float size;
  float area() { return size * size; }
}

struct Circle {
  float r;
  float area() { return r * r * PI; }
}

alias Shape = SuperStruct!(Square, Circle);

// look! polymorphism!
Shape sqr = Square(2);
Shape cir = Circle(4);
Shape[] shapes = [ sqr, cir ];

// call functions that are shared between the source types!
assert(shapes.map!(x => x.area).sum.approxEqual(2 * 2 + 4 * 4 * PI));
```

Notice that there is no explicit interface definition. The 'interface' forms
organically from the common members of the source types.

The interface isn't limited to methods -- common fields can be exposed as well:

```d
// `top` is a field of Square
struct Square {
  int top, left, width, height;
}

// but a property of cirle
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
