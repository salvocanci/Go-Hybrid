fn Greet(name: String) -> String:
    "hello, " + name + " (from Hybrid)"

fn Boom():
    panic "boom from Hybrid source"

fn Main():
    if os.Args[1] == "boom":
        Boom()
    fmt.Println(Greet("world"))
