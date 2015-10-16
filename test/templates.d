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

/* Currently SuperStruct cannot forward templated functions whose compile-time
 * args describe anything other than the types of the runtime args.
 *
 * For example, getVal(T)() cannot be forwarded, as SuperStruct tries to
 * translate it to getVal(T)(T val) as it thinks T describes an argument type.
 *
 */
/++
unittest {
  struct Foo {
    int val;

    auto getVal(T)() {
      return cast(T) val;
    }
  }

  struct Bar {
    int val;

    auto getVal(T)() {
      return cast(T) val;
    }
  }

  SuperStruct!(Foo, Bar) fb = Foo(1);
  assert(fb.getVal!int == 1);
}
++/
