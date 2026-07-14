@file:OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)

package com.hopae.eudi.demo.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.hopae.eudi.demo.R

/** Manrope (variable) — the wallet's UI typeface, matching the design guide. */
private fun manrope(weight: Int) =
    Font(R.font.manrope_variable, weight = FontWeight(weight), variationSettings = FontVariation.Settings(FontVariation.weight(weight)))

val Manrope = FontFamily(
    manrope(400), manrope(500), manrope(600), manrope(700), manrope(800),
)

/** JetBrains Mono (variable) — the debug console and any monospaced values. */
private fun jbMono(weight: Int) =
    Font(R.font.jetbrains_mono_variable, weight = FontWeight(weight), variationSettings = FontVariation.Settings(FontVariation.weight(weight)))

val JetBrainsMono = FontFamily(jbMono(400), jbMono(500))

/**
 * Type scale mapped onto Material3 slots so stock components pick up Manrope automatically.
 * Screen headers use [Typography.titleLarge]; section titles [titleMedium]; buttons [labelLarge].
 */
val WalletTypography = Typography(
    titleLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(800), fontSize = 21.sp, letterSpacing = (-0.3).sp),
    titleMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(800), fontSize = 16.sp, letterSpacing = (-0.2).sp),
    titleSmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(700), fontSize = 14.sp),
    bodyLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(600), fontSize = 14.sp),
    bodyMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(600), fontSize = 13.sp),
    bodySmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(500), fontSize = 12.sp),
    labelLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(700), fontSize = 14.sp),
    labelMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(700), fontSize = 12.sp),
    labelSmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight(700), fontSize = 11.sp, letterSpacing = 0.6.sp),
)

/** An uppercase, tracked section-label style used throughout the design ("DATA TO BE REQUESTED"). */
val SectionLabelStyle = TextStyle(
    fontFamily = Manrope, fontWeight = FontWeight(800), fontSize = 11.5.sp, letterSpacing = 0.8.sp,
)

/** Monospaced style for the debug console. */
val MonoStyle = TextStyle(fontFamily = JetBrainsMono, fontWeight = FontWeight(400), fontSize = 11.sp)
