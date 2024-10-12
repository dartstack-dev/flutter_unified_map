package dev.alphabyte.flutter_unified_map_android

import kotlin.test.Test
import kotlin.test.assertEquals

class IconRefsTest {
    private val refs = IconRefs()

    @Test
    fun anIconIsDroppedWhenItsLastMarkerGoes() {
        refs.registered("pin")
        assertEquals(emptySet(), refs.update(emptyList(), listOf("a" to "pin", "b" to "pin")))
        assertEquals(emptySet(), refs.update(listOf("a"), emptyList()))
        assertEquals(setOf("pin"), refs.update(listOf("b"), emptyList()))
    }

    @Test
    fun aMarkerThatChangesIconReleasesTheOldOne() {
        refs.update(emptyList(), listOf("a" to "pin", "b" to "star"))
        assertEquals(setOf("pin"), refs.update(emptyList(), listOf("a" to "star")))
        assertEquals(emptySet(), refs.update(emptyList(), listOf("a" to "star", "b" to "star")))
    }

    @Test
    fun anIconReleasedAndTakenInTheSameUpdateIsKept() {
        refs.update(emptyList(), listOf("a" to "pin"))
        assertEquals(emptySet(), refs.update(listOf("a"), listOf("b" to "pin")))
        assertEquals(emptySet(), refs.update(emptyList(), listOf("b" to "star", "c" to "pin")))
    }

    @Test
    fun aRegisteredIconNoMarkerUsesIsDroppedWithTheNextUpdate() {
        refs.registered("unused")
        refs.registered("pin")
        assertEquals(setOf("unused"), refs.update(emptyList(), listOf("a" to "pin")))
        assertEquals(emptySet(), refs.update(emptyList(), emptyList()))
    }

    /** The same sequence as the Dart `_IconBook` test 'an icon no marker references any more is sent again'. */
    @Test
    fun followsTheDartBook() {
        refs.update(emptyList(), listOf("a" to "pin", "b" to "pin"))
        assertEquals(emptySet(), refs.update(listOf("a"), emptyList()))
        assertEquals(emptySet(), refs.update(emptyList(), listOf("c" to "pin")))
        refs.registered("star")
        assertEquals(setOf("pin"), refs.update(emptyList(), listOf("b" to "star", "c" to "star")))
        assertEquals(emptySet(), refs.update(emptyList(), listOf("d" to "pin")))
        assertEquals(setOf("star", "pin"), refs.update(listOf("b", "c", "d"), emptyList()))
    }
}
