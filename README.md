SuperStruct
===

- [Code on Github](http://github.com/rcorre/superstruct).
- [Docs hosted on Github](http://rcorre.github.io/superstruct).
- [Dub Package](http://code.dlang.org/packages/superstruct).

# What is it?

It's a `struct`! It's a `class`! No, its ...  `SuperStruct`!

This bastard child of [`wrap`](http://dlang.org/phobos/std_typecons.html#.wrap)
and [`variant`](http://dlang.org/phobos/std_variant.html) works like an
`Algebraic`, but exposes members that are common across the source types.

```d
struct Vector { float x, y; }

struct Square {
  float size;
  Vector topLeft;

  auto area() { return size * size; }

  auto center() {
    return Vector(topLeft.x + size / 2, topLeft.y + size / 2);
  }

  auto center(Vector c) {
    return topLeft = Vector(c.x - size / 2, c.y - size / 2);
  }
}

struct Circle {
  float radius;
  Vector center;
  float area() { return radius * radius * PI; }
}

// Shape may look like a class, but its actually a struct
alias Shape = SuperStruct!(Square, Circle);

Shape sqr = Square(2, Vector(0,0));
Shape cir = Circle(4, Vector(0,0));
Shape[] shapes = [ sqr, cir ];

// call functions that are shared between the source types:
assert(shapes.map!(x => x.area).sum.approxEqual(2 * 2 + 4 * 4 * PI));

// It doesn't matter that `center` is a field of `Circle`, but a property of Square.
// They can be used in the same way:
cir.center = Vector(4, 2);
sqr.center = cir.center;
assert(sqr.center == Vector(4,2));
```

Notice that there is no explicit interface definition. The 'interface' forms
organically from the common members of the source types.

`SuperStruct` exposes common operators too.
For example, it can forward the `opSlice` member of container types as well as
common functions like `insert`:

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
```

# Is it useful?

I don't know, you tell me. I just work here.

If nothing else, its an interesting exercise in what D's compile-time facilities
are capable of.

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

Imagine having to do that `visit` nonesense for every type for each common
member. No fun.

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

## Fields and members
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

- Operators with compatible signatures are exposed:

```d
  SuperStruct!(SList!T, Array!T) list = SList!int(1,2,3);
  list = list ~ [4,5,6]; // SList and Array both support opBinary!"~"
}
```

- If members have compatible signatures but uncommon return types, the exposed
  member returns a `SuperStruct` of the possible return types.

```d
  SuperStruct!(SList!T, Array!T) list = SList!int(1,2,3);

  // opSlice returns a SuperStruct of the SList and Array slice types.
  // as it exposes the common members of both, it looks just like a range.
  assert(list[].equal([1,2,3]));
}
```

- `SuperStruct` exposes a specialized `opEquals` that works against another
  `SuperStruct` of the same type.

```d
  struct A { int i; }
  struct B { int i; }
  struct C { int i; bool opEquals(T)(T other) { return other.i == i; } }

  SuperStruct!(A, B, C) a0 = A(0);
  SuperStruct!(A, B, C) a1 = A(1);
  SuperStruct!(A, B, C) b0 = B(0);
  SuperStruct!(A, B, C) c0 = C(0);

  assert(a0 == a0); // both contain an A with the same value
  assert(a0 != a1); // both contain an A with different values
  assert(a0 != b0); // A and B are not comparable
  assert(a0 == c0); // C is comparable to A
```

- Private members are not exposed.

- Symbols beginning with `__` are not exposed.

# How does it work?
`SuperStruct` mixes in a generic member for each member of the subtypes.
This member tries to forward calls to the underlying member of whatever subtype
it currently contains.

For example, if all source types have a member `foo`, the `SuperStruct` member
might look like:

```d
template foo(TemplateArgs...) {
  auto foo(Args...)(Args args) {
    return visitMember!("%s", TemplateArgs)(_value, args);
  }
}
```

The first layer catches the operator, the second grabs any _explicit_
compile-time parameters (e.g. lambdas), and the third layer grabs any number of
runtime parameters.

Only the explicit compile-time parameters are passed along to the underlying
members, as `Args` can be figured out from the arguments themselves.

Here, `visitMember` is a helper that tries to forward the call to a matching
member on whatever `_value` (an `Algebraic` of the source types) is holding. If
whatever args you pass don't form a valid call on the given member for every
subtype, it won't compile.

If they all do form valid calls but there is no common return type for those
calls, the returned value is a `SuperStruct` of the return types.
