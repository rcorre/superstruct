import superstruct;

// function taking templated args
unittest {
  struct Foo {
    int val;
    auto setVal(T)(T v) { return val = cast(int) v; }
  }

  struct Bar {
    int val;
    auto setVal(T)(T v) { return val = cast(int) v; }
  }

  SuperStruct!(Foo, Bar) fb = Foo(1);
  assert(fb.val == 1);

  fb.setVal(2);
  assert(fb.val == 2);

  fb.setVal(3f);
  assert(fb.val == 3);

  static assert( __traits(compiles, fb.setVal(2f)));
  static assert(!__traits(compiles, fb.setVal("I'm not a number")));
}

// templated source types
unittest {
  struct Foo(T) {
    T field;
    T prop;

    auto fun(T t, int i) { return T.init; }
  }

  struct Bar(T) {
    T field, _hidden;

    auto prop() { return _hidden; }
    auto prop(T val) { return _hidden = val; }

    auto fun(T t, int i) { return T.init; }
  }

  SuperStruct!(Foo!int, Bar!int) fbi = Foo!int(1, 2);
  assert(fbi.field == 1);
  assert(fbi.prop  == 2);

  assert((fbi.field = 3) == 3);
  assert((fbi.prop  = 4) == 4);

  assert(fbi.fun(5, 6) == 0);

  SuperStruct!(Foo!string, Bar!string) fbs = Foo!string("1", "2");
  assert(fbs.field == "1");
  assert(fbs.prop  == "2");

  assert((fbs.field = "3") == "3");
  assert((fbs.prop  = "4") == "4");

  assert(fbs.fun("asdf", 6) == "");
}

// simple templated function
unittest {
  struct Foo {
    auto str(T)() { return T.stringof ~ "-foo"; }
  }

  struct Bar {
    auto str(T)() { return T.stringof ~ "-bar"; }
  }

  SuperStruct!(Foo, Bar) f = Foo();
  SuperStruct!(Foo, Bar) b = Bar();

  assert(f.str!int  == "int-foo");
  assert(b.str!real == "real-bar");
}

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

  alias FooBar = SuperStruct!(Foo, Bar);
  FooBar fb = Foo(3);

  // need to use a static fn here due to unrelated issue:
  // cannot use local 'add1' as parameter to non-global template
  static auto add1 = (int a) => a + 1;
  static auto add2 = (int a) => a + 2;

  assert(fb.noargs!(add1)()        == 4); // 3 + 1
  assert(fb.onearg!(add1)(5)       == 6); // 5 + 1
  assert(fb.twofns!(add1, add2)(5) == 8); // 5 + 1 + 2

  // implicit type args
  assert(fb.onetype(5)      == 8);   // 3 + 5
  assert(fb.twotype(5, 7)   == 15);  // 3 + 5 + 7
  assert(fb.twotype(5f, 7f) == 15f); // 3 + 5 + 7

  // explicit type args
  assert(fb.onetype!(int)(5)             == 8);   // 3 + 5
  assert(fb.twotype!(int)(5, 7)          == 15);  // 3 + 5 + 7
  assert(fb.twotype!(float, float)(5, 7) == 15f); // 3 + 5 + 7

  // only specify some type args
  assert(fb.twotype!(float)(5, 7) == 15f); // 3 + 5 + 7
}
