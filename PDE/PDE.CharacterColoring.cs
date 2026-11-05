using System;
using System.Collections.Generic;

namespace PDE.PowerShell
{
    public static class PDECharacterColoring
    {
        public const int Orange = 1, Red = 2, Green = 3;

        public static int[] Map(string typed, ISet<string> commands, ISet<string> history,
                                bool knownPrefix, bool uncertain, int maximumDistance)
        {
            if (commands.Contains(typed) || knownPrefix)
                return Solid(typed.Length, Green);
            if (uncertain)
                return Solid(typed.Length, Orange);

            maximumDistance = Math.Max(0, Math.Min(4, maximumDistance));
            string best = null;
            int bestDistance = maximumDistance + 1;
            int bestPrefix = -1;
            bool bestInHistory = false;
            foreach (string candidate in commands)
            {
                if (String.IsNullOrEmpty(candidate) || typed.Length - candidate.Length > maximumDistance)
                    continue;

                // For an unfinished name, compare the typed portion to the candidate prefix.
                int length = candidate.Length;
                if (length > typed.Length) {
                    if (typed.Length < 2 || !CharEquals(typed[0], candidate[0])) continue;
                    length = typed.Length;
                }
                int distance = BoundedDistance(typed, candidate, length, maximumDistance);
                if (distance > maximumDistance || distance > bestDistance) continue;
                int prefix = 0;
                while (prefix < typed.Length && prefix < candidate.Length &&
                       CharEquals(typed[prefix], candidate[prefix])) prefix++;
                bool inHistory = history.Contains(candidate);
                if (best == null || distance < bestDistance ||
                    (distance == bestDistance &&
                     (prefix > bestPrefix ||
                      (prefix == bestPrefix &&
                       ((inHistory && !bestInHistory) ||
                        (inHistory == bestInHistory &&
                         String.Compare(candidate, best,
                             StringComparison.OrdinalIgnoreCase) < 0))))))
                {
                    best = candidate;
                    bestDistance = distance;
                    bestPrefix = prefix;
                    bestInHistory = inHistory;
                }
            }
            return best == null ? Solid(typed.Length, Red) : ComparePositions(typed, best);
        }

        // Reserve exact matches first. Each remaining target letter can pay for one orange.
        public static int[] ComparePositions(string typed, string target)
        {
            var colors = Solid(typed.Length, Red);
            var available = new Dictionary<char, int>();
            for (int i = 0; i < target.Length; i++)
            {
                char letter = Char.ToUpperInvariant(target[i]);
                if (i < typed.Length && Char.ToUpperInvariant(typed[i]) == letter)
                {
                    colors[i] = Green;
                    continue;
                }
                int count;
                available.TryGetValue(letter, out count);
                available[letter] = count + 1;
            }

            for (int i = 0; i < typed.Length; i++)
            {
                if (colors[i] == Green) continue;
                char letter = Char.ToUpperInvariant(typed[i]);
                int count;
                if (available.TryGetValue(letter, out count) && count > 0)
                {
                    colors[i] = Orange;
                    available[letter] = count - 1;
                }
            }
            return colors;
        }

        private static int[] Solid(int length, int color)
        {
            var colors = new int[length];
            for (int i = 0; i < length; i++) colors[i] = color;
            return colors;
        }

        private static bool CharEquals(char a, char b)
        {
            return Char.ToUpperInvariant(a) == Char.ToUpperInvariant(b);
        }

        private static int BoundedDistance(string typed, string candidate, int length, int limit)
        {
            int n = typed.Length, m = length;
            if (Math.Abs(n - m) > limit) return limit + 1;
            int[] previous = new int[m + 1];
            for (int j = 0; j <= m; j++) previous[j] = j;
            int[] current = new int[m + 1];
            for (int i = 1; i <= n; i++)
            {
                current[0] = i;
                int minimum = i;
                for (int j = 1; j <= m; j++)
                {
                    int cost = CharEquals(typed[i - 1], candidate[j - 1]) ? 0 : 1;
                    current[j] = Math.Min(Math.Min(previous[j] + 1,
                                                 current[j - 1] + 1),
                                          previous[j - 1] + cost);
                    minimum = Math.Min(minimum, current[j]);
                }
                if (minimum > limit) return limit + 1;
                var swap = previous;
                previous = current;
                current = swap;
            }
            return previous[m];
        }
    }
}
