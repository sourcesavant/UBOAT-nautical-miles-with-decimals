using UBOAT.Game.Core.Serialization;
using UnityEngine;
using HarmonyLib;
using UBOAT.Game;

namespace NauticalMilesWithDecimals
{
    [NonSerializedInGameState]
    public class Main : IUserMod
    {
        public void OnLoaded()
        {
            Harmony harmony = new Harmony("NauticalMilesWithDecimals");
            harmony.PatchAll();
            Debug.Log("Nautical Miles With Decimals loaded!");
        }
    }
}