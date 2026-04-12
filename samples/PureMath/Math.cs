/// <summary>
/// hu: CIL-T0 kompatibilis, pure funkcionális C# metódusok — kizárólag
/// int típussal, statikus metódusokkal, lokális változókkal, és rekurzív /
/// cross-method hívásokkal. Ez a CLI-CPU projekt első valódi „felhasználói
/// programja", amelyet a Roslyn natív pipeline-on át (dotnet build → .dll →
/// TCliCpuLinker → TCpu) futtathatunk.
/// <br />
/// en: CIL-T0 compatible, pure functional C# methods — using only int types,
/// static methods, local variables, and recursive / cross-method calls. This
/// is the CLI-CPU project's first real "user program", runnable through the
/// Roslyn-native pipeline (dotnet build → .dll → TCliCpuLinker → TCpu).
/// </summary>
public static class Math
{
    public static int Add(int a, int b)
    {
        return a + b;
    }

    public static int Fibonacci(int n)
    {
        if (n < 2) return n;
        return Fibonacci(n - 1) + Fibonacci(n - 2);
    }

    public static int Factorial(int n)
    {
        int result = 1;

        for (int i = 2; i <= n; i++)
            result *= i;

        return result;
    }

    public static int Gcd(int a, int b)
    {
        while (b != 0)
        {
            int t = b;
            b = a % b;
            a = t;
        }

        return a;
    }

    public static int Square(int x)
    {
        return x * x;
    }

    public static int SumOfSquares(int a, int b)
    {
        return Square(a) + Square(b);
    }

    public static int IsPrime(int n)
    {
        if (n < 2) return 0;
        if (n < 4) return 1;

        if ((n & 1) == 0) return 0;

        int i = 3;

        while (i * i <= n)
        {
            if (n % i == 0) return 0;
            i += 2;
        }

        return 1;
    }

    public static int Abs(int x)
    {
        return x < 0 ? -x : x;
    }

    public static int Max(int a, int b)
    {
        return a > b ? a : b;
    }

    public static int Min(int a, int b)
    {
        return a < b ? a : b;
    }
}
