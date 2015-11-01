SuperStruct
===

- [Code on Github](http://github.com/rcorre/superstruct).
- [Docs hosted on Github](http://rcorre.github.io/superstruct).
- [Dub Package](http://code.dlang.org/packages/superstruct).

Suppose you've got a few structs representing shapes, `Circle`, `Square`
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

At this point, you should be yelling 'This reeks of boilerplate! Show me some
template magic to solve all my problems!'

# What is it?

It's a `struct`! It's a `class`! No, its ...  `SuperStruct`!

This bastard child of [`wrap`](http://dlang.org/phobos/std_typecons.html#.wrap)
and [`variant`](http://dlang.org/phobos/std_variant.html) works like an
`Algebraic`, but exposes members that are common across the source types.

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

As a more practical example, consider how it could serve as a base type for
various containers in the standard library:

```d
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
```

## Why not use Variant/Algebraic?

To avoid repeating yourself.

```d
// Compare this...
auto alg = Algebraic!(Rect, Ellipse, Triangle)(someShape);
auto center1 = alg.visit!((Rect r)     => r.center,
                          (Ellipse e)  => e.center,
                          (Triangle t) => t.center)

// To this! Easier, right?
auto sup = SuperStruct!(Rect, Ellipse, Triangle)(someShape);
auto center2 = sup.center;
```

## Why not use wrap?

[`std.typecons.wrap`](http://dlang.org/phobos/std_typecons.html#.wrap) and
`SuperStruct` have similar, but not entirely overlapping uses.

1. `wrap` does not _currently_ support structs (but a
   [PR](https://github.com/D-Programming-Language/phobos/pull/2945) exists to
   implement this)
2. `wrap` allocates a class. `SuperStruct` is just a struct.
3. `wrap` requires an explicitly defined interface. `SuperStruct` generates an
   interface automatically.
4. `SuperStruct` can expose common fields directly. `wrap` requires the user to
   manually wrap fields in getter/setter properties to satisfy an interface.

If you actually need a interface that can be implemented without knowing all the
source types in advance, then you probably want `wrap`.

# What does it expose?

- If all types have a matching field, it gets exposed:

```d
struct Foo { int a; }
struct Bar { int a; }
auto foobar = SuperStruct!(Foo, Bar)(Foo(1));
foobar.a = 5;
assert(foobar.a == 5);
```

- If all types have a matching method, all compatible overloads are exposed:

```d
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
```

- If a name refers to a field on one type and a method on another, it is exposed
  if the field and the method have compatible signatures:

```d
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
```

- Private members are not exposed.

# How does it work?
`SuperStruct` uses a catch-all `opDispatch` to forward members to the underlying
types.

```d
template opDispatch(string op) {
  template opDispatch(TemplateArgs...) {
    auto opDispatch(Args...)(Args args) {
      return visitor!(op, TemplateArgs)(_value, args);
    }
  }
}
```

The first layer catches the operator, the second grabs any _explicit_
compile-time parameters (e.g. lambdas), and the third layer grabs any number of
runtime parameters.

Only the explicit compile-time parameters are passed along to the underlying
members, as `Args` can be figured out from the arguments themselves.

Here, `visitor` is a helper that tries to forward the call to a matching member
on whatever `_value` (an `Algebraic` of the source types) is holding. If
whatever args you pass don't form a valid call on the given member for every
subtype, it won't compile. If they all do form valid calls but there is no
common return type for those calls, it won't compile.
