using HarmonyLib;
using UBOAT.Game.UI.Map;
using UBOAT.Game.Core;
using System.Collections.Generic;
using System.Reflection.Emit;
using System.Reflection;
using UnityEngine;
using Cysharp.Text;
using UBOAT.Game.Core.Data;
using System;


namespace NauticalMilesWithDecimals
{
    [HarmonyPatch]
    class NauticalMilesWithDecimalsPatches
    {
        [HarmonyPatch(typeof(MapLineUI), "PlaceLine")]
        [HarmonyPatch(typeof(MapBearingUI), "ValidatePointPositions")]
        static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions)
        {
            var targetMethod = AccessTools.Method(typeof(UnitsUtility), "KilometersToPreferredUnits", new[] { typeof(float), typeof(bool) });
            var instructionList = new List<CodeInstruction>(instructions);

            for (int i = 0; i < instructionList.Count; i++)
            {
                if (instructionList[i].opcode == OpCodes.Call && instructionList[i].operand is MethodInfo method && method == targetMethod)
                {
                    // Check if the previous instruction is ldc.i4.0
                    if (i > 0 && instructionList[i - 1].opcode == OpCodes.Ldc_I4_0)
                    {
                        // Change the previous instruction to ldc.i4.1 (moreDetailed = true)
                        instructionList[i - 1].opcode = OpCodes.Ldc_I4_1;
                        Debug.Log("Patch applied");
                    }
                }
            }

            return instructionList;
        }

        [HarmonyPatch(typeof(UnitsUtility))]
        [HarmonyPatch("KilometersToPreferredUnits")]
        [HarmonyPatch(new Type[]         { typeof(Utf16ValueStringBuilder), typeof(float), typeof(bool) }, 
                      new ArgumentType[] { ArgumentType.Ref, ArgumentType.Normal, ArgumentType.Normal })]
        static bool Prefix(ref Utf16ValueStringBuilder stringBuilder, float value, bool moreDetailed, ref UserSettings ___userSettings, ref string ___cache_nmi, ref string ___cache_cables)
        {
            Units units = ___userSettings.GameplaySettings.units;

            if ((uint)units > 1u && units == Units.Nautical)
            {
                value *= 0.5399568f;
                var locale = Traverse.Create(typeof(UnitsUtility)).Field("locale").GetValue<Locale>();
                moreDetailed = true;
                if (moreDetailed)
                {
                    // Round down to one decimal place
                    float roundedValue = Mathf.Floor(value * 10f) / 10f;
                    stringBuilder.AppendFormat("{0:0.0}", roundedValue);
                    stringBuilder.Append(' ');
                    Debug.Log("Before Local");
                    stringBuilder.Append(___cache_nmi ?? (locale["nmi"]));
                    Traverse.Create(typeof(UnitsUtility)).Field("cache_nmi").SetValue(locale["nmi"]);
                    Debug.Log("After Local");
                }
                else
                {
                    int num = Mathf.FloorToInt(value);
                    if (num != 0)
                    {
                        stringBuilder.Append(num);
                        stringBuilder.Append(' ');
                        stringBuilder.Append(___cache_nmi ?? (locale["nmi"]));
                        Traverse.Create(typeof(UnitsUtility)).Field("cache_nmi").SetValue(locale["nmi"]);
                    }
                    else
                    {
                        int value2 = Mathf.FloorToInt(value * 10f);
                        stringBuilder.Append(value2);
                        stringBuilder.Append(' ');
                        stringBuilder.Append(___cache_cables ?? (locale["cables"]));
                        Traverse.Create(typeof(UnitsUtility)).Field("cache_cables").SetValue(locale["cables"]);
                    }
                }

                return false; // Skip the original method
            }

            return true; // Continue with the original method
        }
    }
}