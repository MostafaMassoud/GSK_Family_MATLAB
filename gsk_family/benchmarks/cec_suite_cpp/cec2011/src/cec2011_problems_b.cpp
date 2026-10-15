// CEC2011 work package B (wpb): problems 9 and 11-20 (power systems).
//
// Ported from the CEC2011 real-world MATLAB package (the reference code):
//   problem 9       cost_fn.m + EBEinputfile.m + EBEformybus.m
//   problems 11-12  MY_FUNCTION_10_1/_10_2.m -> fn_DED_5/fn_DED_10.m
//   problems 13-17  MY_FUNCTION_11_1..5.m -> fn_ELD_6/13/15/40/140.m
//   problems 18-20  MY_FUNCTION_12_1..3.m -> fn_HT_ELD_Case_1/2/3.m
// Dispatch follows Calc_Fitx_2011.m; bounds follow define_boundaries.m.
// Details: docs/reference/cec2011_port_plan.md, section 5 (each problem) and
// section 3 (suite-wide quirks).
//
// [PRESERVE] marks a bug or quirk of the reference code that is kept on
// purpose so results match.
//
// Rounding: for problems 11-20 the MY_FUNCTION_* wrapper rounds x to 4
// decimals, x = round(x*10000)/10000, before calling its fn_* objective.
// Problem 9 calls cost_fn directly and does not round.
//
// The data tables were copied from the .m files by script, not retyped. The
// numeric tokens are unchanged, so each C++ literal parses to the same double
// as in MATLAB. Each table was checked value by value against its source.

#include "cec2011_detail.hpp"

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstddef>
#include <limits>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace gskcec::cec2011::detail {

namespace {

constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();

namespace wpb_data {

// ---- fn_DED_5.m ----

inline constexpr double kDed5Demand[24] = {
    410, 435, 475, 530, 558, 608, 626, 654,
    690, 704, 720, 740, 704, 690, 654, 580,
    558, 608, 654, 704, 680, 605, 527, 463};

inline constexpr double kDed5Data1[5][7] = {
    {10, 75, 0.0080, 2.0, 25, 100, 0.042},
    {20, 125, 0.0030, 1.8, 60, 140, 0.040},
    {30, 175, 0.0012, 2.1, 100, 160, 0.038},
    {40, 250, 0.0010, 2.0, 120, 180, 0.037},
    {50, 300, 0.0015, 1.8, 40, 200, 0.035}};  // [Pmin Pmax a b c e f]

inline constexpr double kDed5Data2[5][7] = {
    {kNaN, 30, 30, 10, 10, 10, 10},
    {kNaN, 30, 30, 20, 20, 20, 20},
    {kNaN, 40, 40, 30, 30, 30, 30},
    {kNaN, 50, 50, 40, 40, 40, 40},
    {kNaN, 50, 50, 50, 50, 50, 50}};  // [Po UR DR Z1lo Z1hi Z2lo Z2hi]; Po is NaN, unused

inline constexpr double kDed5B1[5][5] = {
    {0.000049, 0.000014, 0.000015, 0.000015, 0.000020},
    {0.000014, 0.000045, 0.000016, 0.000020, 0.000018},
    {0.000015, 0.000016, 0.000039, 0.000010, 0.000012},
    {0.000015, 0.000020, 0.000010, 0.000040, 0.000014},
    {0.000020, 0.000018, 0.000012, 0.000014, 0.000035}};

// ---- fn_DED_10.m ----

inline constexpr double kDed10Demand[24] = {
    1036, 1110, 1258, 1406, 1480, 1628, 1702, 1776,
    1924, 2072, 2146, 2220, 2072, 1924, 1776, 1554,
    1480, 1628, 1776, 2072, 1924, 1628, 1332, 1184};

inline constexpr double kDed10Data1[10][7] = {
    {150, 470, 0.00043, 21.60, 958.20, 450, 0.041},
    {135, 460, 0.00063, 21.05, 1313.6, 600, 0.036},
    {73, 340, 0.00039, 20.81, 604.97, 320, 0.028},
    {60, 300, 0.00070, 23.90, 471.60, 260, 0.052},
    {73, 243, 0.00079, 21.62, 480.29, 280, 0.063},
    {57, 160, 0.00056, 17.87, 601.75, 310, 0.048},
    {20, 130, 0.00211, 16.51, 502.7, 300, 0.086},
    {47, 120, 0.0048, 23.23, 639.40, 340, 0.082},
    {20, 80, 0.10908, 19.58, 455.60, 270, 0.098},
    {55, 55, 0.00951, 22.54, 692.4, 380, 0.094}};  // [Pmin Pmax a b c e f]

inline constexpr double kDed10Data2[10][3] = {
    {kNaN, 80, 80},
    {kNaN, 80, 80},
    {kNaN, 80, 80},
    {kNaN, 50, 50},
    {kNaN, 50, 50},
    {kNaN, 50, 50},
    {kNaN, 30, 30},
    {kNaN, 30, 30},
    {kNaN, 30, 30},
    {kNaN, 30, 30}};  // [Po UR DR]; Po is NaN, unused; no POZ columns

// ---- fn_ELD_6.m ----

inline constexpr double kEld6Data1[6][5] = {
    {100, 500, 0.0070, 7.0, 240},
    {50, 200, 0.0095, 10.0, 200},
    {80, 300, 0.0090, 8.5, 220},
    {50, 150, 0.0090, 11.0, 200},
    {50, 200, 0.0080, 10.5, 220},
    {50, 120, 0.0075, 12.0, 190}};  // [Pmin Pmax a b c]

inline constexpr double kEld6Data2[6][7] = {
    {440, 80, 120, 210, 240, 350, 380},
    {170, 50, 90, 90, 110, 140, 160},
    {200, 65, 100, 150, 170, 210, 240},
    {150, 50, 90, 80, 90, 110, 120},
    {190, 50, 90, 90, 110, 140, 150},
    {150, 50, 90, 75, 85, 100, 105}};  // [Po UR DR Z1lo Z1hi Z2lo Z2hi]

inline constexpr double kEld6B1Raw[6][6] = {
    {1.7, 1.2, 0.7, -0.1, -0.5, -0.2},
    {1.2, 1.4, 0.9, 0.1, -0.6, -0.1},
    {0.7, 0.9, 3.1, 0.0, -1.0, -0.6},
    {-0.1, 0.1, 0.0, 0.24, -0.6, -0.8},
    {-0.5, -0.6, -0.1, -0.6, 12.9, -0.2},
    {0.2, -0.1, -0.6, -0.8, -0.2, 15.0}};  // scaled by 1e-5 in code

inline constexpr double kEld6B2Raw[6] = {
    -0.3908, -0.1297, 0.7047, 0.0591, 0.2161, -0.6635};  // scaled by 1e-5 in code

// ---- fn_ELD_13.m ----

inline constexpr double kEld13Data1[13][7] = {
    {0, 680, 0.00028, 8.1, 550, 300, 0.035},
    {0, 360, 0.00056, 8.1, 309, 200, 0.042},
    {0, 360, 0.00056, 8.1, 307, 200, 0.042},
    {60, 180, 0.00324, 7.74, 240, 150, 0.063},
    {60, 180, 0.00324, 7.74, 240, 150, 0.063},
    {60, 180, 0.00324, 7.74, 240, 150, 0.063},
    {60, 180, 0.00324, 7.74, 240, 150, 0.063},
    {60, 180, 0.00324, 7.74, 240, 150, 0.063},
    {60, 180, 0.00324, 7.74, 240, 150, 0.063},
    {40, 120, 0.00284, 8.6, 126, 100, 0.084},
    {40, 120, 0.00284, 8.6, 126, 100, 0.084},
    {55, 120, 0.00284, 8.6, 126, 100, 0.084},
    {55, 120, 0.00284, 8.6, 126, 100, 0.084}};  // [Pmin Pmax a b c e f]

// ---- fn_ELD_15.m ----

inline constexpr double kEld15Data1[15][5] = {
    {150, 455, 0.000299, 10.1, 671},
    {150, 455, 0.000183, 10.2, 574},
    {20, 130, 0.001126, 8.8, 374},
    {20, 130, 0.001126, 8.8, 374},
    {150, 470, 0.000205, 10.4, 461},
    {135, 460, 0.000301, 10.1, 630},
    {135, 465, 0.000364, 9.8, 548},
    {60, 300, 0.000338, 11.2, 227},
    {25, 162, 0.000807, 11.2, 173},
    {25, 160, 0.001203, 10.7, 175},
    {20, 80, 0.003586, 10.2, 186},
    {20, 80, 0.005513, 9.9, 230},
    {25, 85, 0.000371, 13.1, 225},
    {15, 55, 0.001929, 12.1, 309},
    {15, 55, 0.004447, 12.4, 323}};  // [Pmin Pmax a b c]

inline constexpr double kEld15Data2[15][9] = {
    {400, 80, 120, 150, 150, 150, 150, 150, 150},
    {300, 80, 120, 185, 255, 305, 335, 420, 450},
    {105, 130, 130, 20, 20, 20, 20, 20, 20},
    {100, 130, 130, 20, 20, 20, 20, 20, 20},
    {90, 80, 120, 180, 200, 305, 335, 390, 420},
    {400, 80, 120, 230, 255, 365, 395, 430, 455},
    {350, 80, 120, 135, 135, 135, 135, 135, 135},
    {95, 65, 100, 60, 60, 60, 60, 60, 60},
    {105, 60, 100, 25, 25, 25, 25, 25, 25},
    {110, 60, 100, 25, 25, 25, 25, 25, 25},
    {60, 80, 80, 20, 20, 20, 20, 20, 20},
    {40, 80, 80, 30, 40, 55, 65, 20, 20},
    {30, 80, 80, 25, 25, 25, 25, 25, 25},
    {20, 55, 55, 15, 15, 15, 15, 15, 15},
    {20, 55, 55, 15, 15, 15, 15, 15, 15}};  // [Po UR DR Z1lo Z1hi Z2lo Z2hi Z3lo Z3hi]

inline constexpr double kEld15B1Raw[15][15] = {
    {1.4, 1.2, 0.7, -0.1, -0.3, -0.1, -0.1, -0.1, -0.3, -0.5, -0.3, -0.2, 0.4, 0.3, -0.1},
    {1.2, 1.5, 1.3, 0.0, -0.5, -0.2, 0.0, 0.1, -0.2, -0.4, -0.4, 0.0, 0.4, 1, -0.2},
    {0.7, 1.3, 7.6, -0.1, -1.3, -0.9, -0.1, 0.0, -0.8, -1.2, -1.7, 0.0, -2.6, 11.1, -2.8},
    {-0.1, 0.0, -0.1, 3.4, -0.7, -0.4, 1.1, 5.0, 2.9, 3.2, -1.1, 0.0, 0.1, 0.1, -2.6},
    {-0.3, -0.5, -1.3, -0.7, 9.0, 1.4, -0.3, -1.2, -1.0, -1.3, 0.7, -0.2, -0.2, -2.4, -0.3},
    {-0.1, -0.2, -0.9, -0.4, 1.4, 1.6, 0.0, -0.6, -0.5, -0.8, 1.1, -0.1, -0.2, -1.7, 0.3},
    {-0.1, 0.0, -0.1, 1.1, -0.3, 0.0, 1.5, 1.7, 1.5, 0.9, -0.5, 0.7, 0.0, -0.2, -0.8},
    {-0.1, 0.1, 0.0, 5.0, -1.2, -0.6, 1.7, 16.8, 8.2, 7.9, -2.3, -3.6, 0.1, 0.5, -7.8},
    {-0.3, -0.2, -0.8, 2.9, -1.0, -0.5, 1.5, 8.2, 12.9, 11.6, -2.1, -2.5, 0.7, -1.2, -7.2},
    {-0.5, -0.4, -1.2, 3.2, -1.3, -0.8, 0.9, 7.9, 11.6, 20.0, -2.7, -3.4, 0.9, -1.1, -8.8},
    {-0.3, -0.4, -1.7, -1.1, 0.7, 1.1, -0.5, -2.3, -2.1, -2.7, 14.0, 0.1, 0.4, -3.8, 16.8},
    {-0.2, 0.0, 0.0, 0.0, -0.2, -0.1, 0.7, -3.6, -2.5, -3.4, 0.1, 5.4, -0.1, -0.4, 2.8},
    {0.4, 0.4, -2.6, 0.1, -0.2, -0.2, 0.0, 0.1, 0.7, 0.9, 0.4, -0.1, 10.3, -10.1, 2.8},
    {0.3, 1.0, 11.1, 0.1, -2.4, -1.7, -0.2, 0.5, -1.2, -1.1, -3.8, -0.4, -10.1, 57.8, -9.4},
    {-0.1, -0.2, -2.8, -2.6, -0.3, 0.3, -0.8, -7.8, -7.2, -8.8, 16.8, 2.8, 2.8, -9.4, 128.3}};  // scaled by 1e-5 in code

inline constexpr double kEld15B2Raw[15] = {
    -0.1, -0.2, 2.8, -0.1, 0.1, -0.3, -0.2, -0.2,
    0.6, 3.9, -1.7, 0.0, -3.2, 6.7, -6.4};  // scaled by 1e-5 in code

// ---- fn_ELD_40.m ----

inline constexpr double kEld40Data1[40][7] = {
    {36, 114, 0.0069, 6.73, 94.705, 100, 0.084},
    {36, 114, 0.0069, 6.73, 94.705, 100, 0.084},
    {60, 120, 0.02028, 7.07, 309.54, 100, 0.084},
    {80, 190, 0.00942, 8.18, 369.03, 150, 0.063},
    {47, 97, 0.0114, 5.35, 148.89, 120, 0.077},
    {68, 140, 0.01142, 8.05, 222.33, 100, 0.084},
    {110, 300, 0.00357, 8.03, 287.71, 200, 0.042},
    {135, 300, 0.00492, 6.99, 391.98, 200, 0.042},
    {135, 300, 0.00573, 6.6, 455.76, 200, 0.042},
    {130, 300, 0.00605, 12.9, 722.82, 200, 0.042},
    {94, 375, 0.00515, 12.9, 635.2, 200, 0.042},
    {94, 375, 0.00569, 12.8, 654.69, 200, 0.042},
    {125, 500, 0.00421, 12.5, 913.4, 300, 0.035},
    {125, 500, 0.00752, 8.84, 1760.4, 300, 0.035},
    {125, 500, 0.00708, 9.15, 1728.3, 300, 0.035},
    {125, 500, 0.00708, 9.15, 1728.3, 300, 0.035},
    {220, 500, 0.00313, 7.97, 647.85, 300, 0.035},
    {220, 500, 0.00313, 7.95, 649.69, 300, 0.035},
    {242, 550, 0.00313, 7.97, 647.83, 300, 0.035},
    {242, 550, 0.00313, 7.97, 647.81, 300, 0.035},
    {254, 550, 0.00298, 6.63, 785.96, 300, 0.035},
    {254, 550, 0.00298, 6.63, 785.96, 300, 0.035},
    {254, 550, 0.00284, 6.66, 794.53, 300, 0.035},
    {254, 550, 0.00284, 6.66, 794.53, 300, 0.035},
    {254, 550, 0.00277, 7.1, 801.32, 300, 0.035},
    {254, 550, 0.00277, 7.1, 801.32, 300, 0.035},
    {10, 150, 0.52124, 3.33, 1055.1, 120, 0.077},
    {10, 150, 0.52124, 3.33, 1055.1, 120, 0.077},
    {10, 150, 0.52124, 3.33, 1055.1, 120, 0.077},
    {47, 97, 0.0114, 5.35, 148.89, 120, 0.077},
    {60, 190, 0.0016, 6.43, 222.92, 150, 0.063},
    {60, 190, 0.0016, 6.43, 222.92, 150, 0.063},
    {60, 190, 0.0016, 6.43, 222.92, 150, 0.063},
    {90, 200, 0.0001, 8.95, 107.87, 200, 0.042},
    {90, 200, 0.0001, 8.62, 116.58, 200, 0.042},
    {90, 200, 0.0001, 8.62, 116.58, 200, 0.042},
    {25, 110, 0.0161, 5.88, 307.45, 80, 0.098},
    {25, 110, 0.0161, 5.88, 307.45, 80, 0.098},
    {25, 110, 0.0161, 5.88, 307.45, 80, 0.098},
    {242, 550, 0.00313, 7.97, 647.83, 300, 0.035}};  // [Pmin Pmax a b c e f]

// ---- fn_ELD_140.m ----

inline constexpr double kEld140Data1[140][5] = {
    {71, 119, 1220.645, 61.242, 0.032888},
    {120, 189, 1315.118, 41.095, 0.00828},
    {125, 190, 874.288, 46.31, 0.003849},
    {125, 190, 874.288, 46.31, 0.003849},
    {90, 190, 1976.469, 54.242, 0.042468},
    {90, 190, 1338.087, 61.215, 0.014992},
    {280, 490, 1818.299, 11.791, 0.007039},
    {280, 490, 1133.978, 15.055, 0.003079},
    {260, 496, 1320.636, 13.226, 0.005063},
    {260, 496, 1320.636, 13.226, 0.005063},
    {260, 496, 1320.636, 13.226, 0.005063},
    {260, 496, 1106.539, 14.498, 0.003552},
    {260, 506, 1176.504, 14.651, 0.003901},
    {260, 509, 1176.504, 14.651, 0.003901},
    {260, 506, 1176.504, 14.651, 0.003901},
    {260, 505, 1176.504, 14.651, 0.003901},
    {260, 506, 1017.406, 15.669, 0.002393},
    {260, 506, 1017.406, 15.669, 0.002393},
    {260, 505, 1229.131, 14.656, 0.003684},
    {260, 505, 1229.131, 14.656, 0.003684},
    {260, 505, 1229.131, 14.656, 0.003684},
    {260, 505, 1229.131, 14.656, 0.003684},
    {260, 505, 1267.894, 14.378, 0.004004},
    {260, 505, 1229.131, 14.656, 0.003684},
    {280, 537, 975.926, 16.261, 0.001619},
    {280, 537, 1532.093, 13.362, 0.005093},
    {280, 549, 641.989, 17.203, 0.000993},
    {280, 549, 641.989, 17.203, 0.000993},
    {260, 501, 911.533, 15.274, 0.002473},
    {260, 501, 910.533, 15.212, 0.002547},
    {260, 506, 1074.81, 15.033, 0.003542},
    {260, 506, 1074.81, 15.033, 0.003542},
    {260, 506, 1074.81, 15.033, 0.003542},
    {260, 506, 1074.81, 15.033, 0.003542},
    {260, 500, 1278.46, 13.992, 0.003132},
    {260, 500, 861.742, 15.679, 0.001323},
    {120, 241, 408.834, 16.542, 0.00295},
    {120, 241, 408.834, 16.542, 0.00295},
    {423, 774, 1288.815, 16.518, 0.000991},
    {423, 769, 1436.251, 15.815, 0.001581},
    {3, 19, 699.988, 75.464, 0.90236},
    {3, 28, 134.544, 129.544, 0.110295},
    {160, 250, 3427.912, 56.613, 0.024493},
    {160, 250, 3751.772, 54.451, 0.029156},
    {160, 250, 3918.78, 54.736, 0.024667},
    {160, 250, 3379.58, 58.034, 0.016517},
    {160, 250, 3345.296, 55.981, 0.026584},
    {160, 250, 3138.754, 61.52, 0.00754},
    {160, 250, 3453.05, 58.635, 0.01643},
    {160, 250, 5119.3, 44.647, 0.045934},
    {165, 504, 1898.415, 71.584, 0.000044},
    {165, 504, 1898.415, 71.584, 0.000044},
    {165, 504, 1898.415, 71.584, 0.000044},
    {165, 504, 1898.415, 71.584, 0.000044},
    {180, 471, 2473.39, 85.12, 0.002528},
    {180, 561, 2781.705, 87.682, 0.000131},
    {103, 341, 5515.508, 69.532, 0.010372},
    {198, 617, 3478.3, 78.339, 0.007627},
    {100, 312, 6240.909, 58.172, 0.012464},
    {153, 471, 9960.11, 46.636, 0.039441},
    {163, 500, 3671.997, 76.947, 0.007278},
    {95, 302, 1837.383, 80.761, 0.000044},
    {160, 511, 3108.395, 70.136, 0.000044},
    {160, 511, 3108.395, 70.136, 0.000044},
    {196, 490, 7095.484, 49.84, 0.018827},
    {196, 490, 3392.732, 65.404, 0.010852},
    {196, 490, 7095.484, 49.84, 0.018827},
    {196, 490, 7095.484, 49.84, 0.018827},
    {130, 432, 4288.32, 66.465, 0.03456},
    {130, 432, 13813.001, 22.941, 0.08154},
    {137, 455, 4435.493, 64.314, 0.023534},
    {137, 455, 9750.75, 45.017, 0.035475},
    {195, 541, 1042.366, 70.644, 0.000915},
    {175, 536, 1159.895, 70.959, 0.000044},
    {175, 540, 1159.895, 70.959, 0.000044},
    {175, 538, 1303.99, 70.302, 0.001307},
    {175, 540, 1156.193, 70.662, 0.000392},
    {330, 574, 2118.968, 71.101, 0.000087},
    {160, 531, 779.519, 37.854, 0.000521},
    {160, 531, 829.888, 37.768, 0.000498},
    {200, 542, 2333.69, 67.983, 0.001046},
    {56, 132, 2028.954, 77.838, 0.13205},
    {115, 245, 4412.017, 63.671, 0.096968},
    {115, 245, 2982.219, 79.458, 0.054868},
    {115, 245, 2982.219, 79.458, 0.054868},
    {207, 307, 3174.939, 93.966, 0.014382},
    {207, 307, 3218.359, 94.723, 0.013161},
    {175, 345, 3723.822, 66.919, 0.016033},
    {175, 345, 3551.405, 68.185, 0.013653},
    {175, 345, 4332.615, 60.821, 0.028148},
    {175, 345, 3493.739, 68.551, 0.01347},
    {360, 580, 226.799, 2.842, 0.000064},
    {415, 645, 382.932, 2.946, 0.000252},
    {795, 984, 156.987, 3.096, 0.000022},
    {795, 978, 154.484, 3.04, 0.000022},
    {578, 682, 332.834, 1.709, 0.000203},
    {615, 720, 326.599, 1.668, 0.000198},
    {612, 718, 345.306, 1.789, 0.000215},
    {612, 720, 350.372, 1.815, 0.000218},
    {758, 964, 370.377, 2.726, 0.000193},
    {755, 958, 367.067, 2.732, 0.000197},
    {750, 1007, 124.875, 2.651, 0.000324},
    {750, 1006, 130.785, 2.798, 0.000344},
    {713, 1013, 878.746, 1.595, 0.00069},
    {718, 1020, 827.959, 1.503, 0.00065},
    {791, 954, 432.007, 2.425, 0.000233},
    {786, 952, 445.606, 2.499, 0.000239},
    {795, 1006, 467.223, 2.674, 0.000261},
    {795, 1013, 475.94, 2.692, 0.000259},
    {795, 1021, 899.462, 1.633, 0.000707},
    {795, 1015, 1000.367, 1.816, 0.000786},
    {94, 203, 1269.132, 89.83, 0.014355},
    {94, 203, 1269.132, 89.83, 0.014355},
    {94, 203, 1269.132, 89.83, 0.014355},
    {244, 379, 4965.124, 64.125, 0.030266},
    {244, 379, 4965.124, 64.125, 0.030266},
    {244, 379, 4965.124, 64.125, 0.030266},
    {95, 190, 2243.185, 76.129, 0.024027},
    {95, 189, 2290.381, 81.805, 0.00158},
    {116, 194, 1681.533, 81.14, 0.022095},
    {175, 321, 6743.302, 46.665, 0.07681},
    {2, 19, 394.398, 78.412, 0.953443},
    {4, 59, 1243.165, 112.088, 0.000044},
    {15, 83, 1454.74, 90.871, 0.072468},
    {9, 53, 1011.051, 97.116, 0.000448},
    {12, 37, 909.269, 83.244, 0.599112},
    {10, 34, 689.378, 95.665, 0.244706},
    {112, 373, 1443.792, 91.202, 0.000042},
    {4, 20, 535.553, 104.501, 0.085145},
    {5, 38, 617.734, 83.015, 0.524718},
    {5, 19, 90.966, 127.795, 0.176515},
    {50, 98, 974.447, 77.929, 0.063414},
    {5, 10, 263.81, 92.779, 2.740485},
    {42, 74, 1335.594, 80.95, 0.112438},
    {42, 74, 1033.871, 89.073, 0.041529},
    {41, 105, 1391.325, 161.288, 0.000911},
    {17, 51, 4477.11, 161.829, 0.005245},
    {7, 19, 57.794, 84.972, 0.234787},
    {7, 19, 57.794, 84.972, 0.234787},
    {26, 40, 1258.437, 16.087, 1.111878}};  // [Pmin Pmax c b a]: cost columns in reverse order

inline constexpr double kEld140Data2[140][3] = {
    {98.4, 30, 120},
    {134, 30, 120},
    {141.5, 60, 60},
    {183.3, 60, 60},
    {125, 150, 150},
    {91.3, 150, 150},
    {401.1, 180, 300},
    {329.5, 180, 300},
    {386.1, 300, 510},
    {427.3, 300, 510},
    {412.2, 300, 510},
    {370.1, 300, 510},
    {301.8, 600, 600},
    {368, 600, 600},
    {301.9, 600, 600},
    {476.4, 600, 600},
    {283.1, 600, 600},
    {414.1, 600, 600},
    {328, 600, 600},
    {389.4, 600, 600},
    {354.7, 600, 600},
    {262, 600, 600},
    {461.5, 600, 600},
    {371.6, 600, 600},
    {462.6, 300, 300},
    {379.2, 300, 300},
    {530.8, 360, 360},
    {391.9, 360, 360},
    {480.1, 180, 180},
    {319, 180, 180},
    {329.5, 600, 600},
    {333.8, 600, 600},
    {390, 600, 600},
    {432, 600, 600},
    {402, 660, 660},
    {428, 900, 900},
    {178.4, 180, 180},
    {194.1, 180, 180},
    {474, 600, 600},
    {609.8, 600, 600},
    {17.8, 210, 210},
    {6.9, 366, 366},
    {224.3, 702, 702},
    {210, 702, 702},
    {212, 702, 702},
    {200.8, 702, 702},
    {220, 702, 702},
    {232.9, 702, 702},
    {168, 702, 702},
    {208.4, 702, 702},
    {443.9, 1350, 1350},
    {426.0, 1350, 1350},
    {434.1, 1350, 1350},
    {402.5, 1350, 1350},
    {357.4, 1350, 1350},
    {423, 720, 720},
    {220, 720, 720},
    {369.4, 2700, 2700},
    {273.5, 1500, 1500},
    {336, 1656, 1656},
    {432, 2160, 2160},
    {220, 900, 900},
    {410.6, 1200, 1200},
    {422.7, 1200, 1200},
    {351, 1014, 1014},
    {296, 1014, 1014},
    {411.1, 1014, 1014},
    {263.2, 1014, 1014},
    {370.3, 1350, 1350},
    {418.7, 1350, 1350},
    {409.6, 1350, 1350},
    {412, 1350, 1350},
    {423.2, 780, 780},
    {428, 1650, 1650},
    {436, 1650, 1650},
    {428, 1650, 1650},
    {425, 1650, 1650},
    {497.2, 1620, 1620},
    {510, 1482, 1482},
    {470, 1482, 1482},
    {464.1, 1668, 1668},
    {118.1, 120, 120},
    {141.3, 180, 180},
    {132, 120, 180},
    {135, 120, 180},
    {252, 120, 180},
    {221, 120, 180},
    {245.9, 318, 318},
    {247.9, 318, 318},
    {183.6, 318, 318},
    {288, 318, 318},
    {557.4, 18, 18},
    {529.5, 18, 18},
    {800.8, 36, 36},
    {801.5, 36, 36},
    {582.7, 138, 204},
    {680.7, 144, 216},
    {670.7, 144, 216},
    {651.7, 144, 216},
    {921, 48, 48},
    {916.8, 48, 48},
    {911.9, 36, 54},
    {898, 36, 54},
    {905, 30, 30},
    {846.5, 30, 30},
    {850.9, 30, 30},
    {843.7, 30, 30},
    {841.4, 36, 36},
    {835.7, 36, 36},
    {828.8, 36, 36},
    {846, 36, 36},
    {179, 120, 120},
    {120.8, 120, 120},
    {121, 120, 120},
    {317.4, 480, 480},
    {318.4, 480, 480},
    {335.8, 480, 480},
    {151, 240, 240},
    {129.5, 240, 240},
    {130, 120, 120},
    {218.9, 180, 180},
    {5.4, 90, 90},
    {45, 90, 90},
    {20, 300, 300},
    {16.3, 162, 162},
    {20, 114, 114},
    {22.1, 120, 120},
    {125, 1080, 1080},
    {10, 60, 60},
    {13, 66, 66},
    {7.5, 12, 6},
    {53.2, 300, 300},
    {6.4, 6, 6},
    {69.1, 60, 60},
    {49.9, 60, 60},
    {91, 528, 528},
    {41, 300, 300},
    {13.7, 18, 30},
    {7.4, 18, 30},
    {28.6, 72, 120}};  // [Po UR DR]

inline constexpr double kEld140Data3[12][3] = {
    {5, 700, 0.080},
    {10, 600, 0.055},
    {15, 800, 0.060},
    {22, 600, 0.050},
    {33, 600, 0.043},
    {40, 600, 0.043},
    {52, 1100, 0.043},
    {70, 1200, 0.030},
    {72, 1000, 0.050},
    {84, 1000, 0.050},
    {119, 600, 0.070},
    {121, 1200, 0.043}};  // [unit e f]: valve-point data for these units

inline constexpr double kEld140Data4[4][7] = {
    {8, 250, 280, 305, 335, 420, 450},
    {32, 220, 250, 320, 350, 390, 420},
    {74, 230, 255, 365, 395, 430, 455},
    {136, 50, 75, 85, 95, 0, 0}};  // [unit Z1lo Z1hi Z2lo Z2hi Z3lo Z3hi]: POZ data

// ---- fn_HT_ELD_Case_1/2/3.m (shared data) ----

inline constexpr double kHtDemand[24] = {
    1370, 1390, 1360, 1290, 1290, 1410, 1650, 2000,
    2240, 2320, 2230, 2310, 2230, 2200, 2130, 2070,
    2130, 2140, 2240, 2280, 2240, 2120, 1850, 1590};

inline constexpr double kHtCCoefficients[4][6] = {
    {-0.0042, -0.42, 0.030, 0.90, 10.0, -50},
    {-0.0040, -0.30, 0.015, 1.14, 9.5, -70},
    {-0.0016, -0.30, 0.014, 0.55, 5.5, -40},
    {-0.0030, -0.31, 0.027, 1.44, 14.0, -90}};  // [c1 c2 c3 c4 c5 c6] per hydro plant

inline constexpr double kHtInflowRate[4][24] = {
    {10, 9, 8, 7, 6, 7, 8, 9, 10, 11, 12, 10, 11, 12, 11, 10, 9, 8, 7, 6, 7, 8, 9, 10},
    {8, 8, 9, 9, 8, 7, 6, 7, 8, 9, 9, 8, 8, 9, 9, 8, 7, 6, 7, 8, 9, 9, 8, 8},
    {8.1, 8.2, 4, 2, 3, 4, 3, 2, 1, 1, 1, 2, 4, 3, 3, 2, 2, 2, 1, 1, 2, 2, 1, 0},
    {2.8, 2.4, 1.6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}};

// ---- EBEinputfile.m ----

inline constexpr double kEbeBusSpec[30][11] = {
    {1, 1, 1.05, 0.0, 0.0, 0.0, 165.9, 0, 0, 0, 0.000},
    {2, 2, 1.043, 0.0, 21.7, 12.7, 49.1, 28.4, -40, 50, 0.000},
    {3, 0, 1.00, 0.0, 2.4, 1.2, 0.0, 0.0, 0, 0, 0.000},
    {4, 0, 1.00, 0.0, 7.6, 1.6, 0.0, 0.0, 0, 0, 0.0},
    {5, 2, 1.01, 0.0, 94.2, 19.0, 21.6, 28, -40, 40, 0.0},
    {6, 0, 1.00, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0},
    {7, 0, 1.00, 0.0, 22.8, 10.9, 0.0, 0.0, 0, 0, 0.0},
    {8, 2, 1.01, 0.0, 30.0, 30.0, 22.8, 39.1, -6, 24, 0.0},
    {9, 0, 1.00, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0},
    {10, 0, 1.00, 0.0, 5.8, 2.0, 0.0, 0.0, -6, 24, 0.0},
    {11, 2, 1.082, 0.0, 0.0, 0.0, 12.4, 31.6, 0, 0, 0.0},
    {12, 0, 1.00, 0.0, 11.2, 7.5, 0.0, 0.0, 0, 0, 0.0},
    {13, 2, 1.071, 0.0, 0.0, 0.0, 11.6, 45.7, 0, 0, 0.0},
    {14, 0, 1.0, 0.0, 6.2, 1.6, 0.0, 0.0, 0, 0, 0.0},
    {15, 0, 1.0, 0.0, 8.2, 2.5, 0.0, 0.0, 0, 0, 0.0},
    {16, 0, 1.0, 0.0, 3.5, 1.8, 0.0, 0.0, 0, 0, 0.0},
    {17, 0, 1.0, 0.0, 9.0, 5.8, 0.0, 0.0, 0, 0, 0.0},
    {18, 0, 1.0, 0.0, 3.2, 0.9, 0.0, 0.0, 0, 0, 0.0},
    {19, 0, 1.0, 0.0, 9.5, 3.4, 0.0, 0.0, 0, 0, 0.0},
    {20, 0, 1.0, 0.0, 2.2, 0.7, 0.0, 0.0, 0, 0, 0.0},
    {21, 0, 1.0, 0.0, 17.5, 11.2, 0.0, 0.0, 0, 0, 0.0},
    {22, 0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0},
    {23, 0, 1.0, 0.0, 3.2, 1.6, 0.0, 0.0, 0, 0, 0.0},
    {24, 0, 1.0, 0.0, 8.7, 6.7, 0.0, 0.0, 0, 0, 0.0},
    {25, 0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0},
    {26, 0, 1.0, 0.0, 3.5, 2.3, 0.0, 0.0, 0, 0, 0.0},
    {27, 0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0},
    {28, 0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0},
    {29, 0, 1.0, 0.0, 2.4, 0.9, 0.0, 0.0, 0, 0, 0.0},
    {30, 0, 1.0, 0.0, 10.6, 1.9, 0.0, 0.0, 0, 0, 0.0}};  // [No Code Vmag Adeg LoadMW LoadMvar GenMW GenMvar Qmin Qmax InjMvar]

inline constexpr double kEbeLineData[41][7] = {
    {1, 2, 0.0192, +0.0575, 0.0264, 1, 130.00},
    {1, 3, 0.0452, +0.1652, 0.0204, 1, 130.0000},
    {2, 4, 0.0570, +0.1737, 0.0184, 1, 65.0000},
    {3, 4, 0.0132, +0.0379, 0.0042, 1, 130},
    {2, 5, 0.0472, +0.1983, 0.0209, 1, 130},
    {2, 6, 0.0581, +0.1763, 0.0187, 1, 65},
    {4, 6, 0.0119, +0.0414, 0.0045, 1, 90},
    {7, 5, 0.0460, +0.1160, 0.0102, 1, 70},
    {6, 7, 0.0267, +0.0820, 0.0085, 1, 130},
    {6, 8, 0.0120, +0.0420, 0.0045, 1, 32},
    {6, 9, 0.0000, +0.2080, 0.0, 1, 65},
    {6, 10, 0.0000, +0.5560, 0.0, 1, 32},
    {11, 9, 0.0000, +0.2080, 0.0, 1, 65},
    {9, 10, 0.0000, +0.1100, 0.0, 1, 65},
    {4, 12, 0.0000, +0.2560, 0.0, 1, 65},
    {13, 12, 0.0000, +0.1400, 0.0, 1, 65},
    {12, 14, 0.1231, +0.2559, 0.0, 1, 32},
    {12, 15, 0.0662, +0.1304, 0.0, 1, 32},
    {12, 16, 0.0945, +0.1987, 0.0, 1, 32},
    {14, 15, 0.2210, +0.1997, 0.0, 1, 16},
    {16, 17, 0.0524, +0.1923, 0.0, 1, 16},
    {15, 18, 0.1073, +0.2185, 0.0, 1, 16},
    {18, 19, 0.0639, +0.1292, 0.0, 1, 16},
    {20, 19, 0.0340, +0.0680, 0.0, 1, 32},
    {10, 20, 0.0936, +0.2090, 0.0, 1, 32},
    {10, 17, 0.0324, +0.0845, 0.0, 1, 32},
    {10, 21, 0.0348, +0.0749, 0.0, 1, 32},
    {10, 22, 0.0727, +0.1499, 0.0, 1, 32},
    {22, 21, 0.0116, +0.0236, 0.0, 1, 32},
    {15, 23, 0.1000, +0.2020, 0.0, 1, 16},
    {22, 24, 0.1150, +0.1790, 0.0, 1, 16},
    {23, 24, 0.1320, +0.2700, 0.0, 1, 16},
    {25, 24, 0.1885, +0.3292, 0.0, 1, 16},
    {25, 26, 0.2544, +0.3800, 0.0, 1, 16},
    {27, 25, 0.1093, +0.2087, 0.0, 1, 16},
    {28, 27, 0.0000, +0.3960, 0.0, 1, 65},
    {27, 29, 0.2198, +0.4153, 0.0, 1, 16},
    {27, 30, 0.3202, +0.6027, 0.0, 1, 16},
    {29, 30, 0.2399, +0.4533, 0.0, 1, 16},
    {8, 28, 0.0636, +0.2000, 0.0214, 1, 32},
    {6, 28, 0.0169, +0.0599, 0.0065, 1, 32}};  // [from to R X halfB tap limit]; complex column 3 (R+jX) split into R, X

// ---- cost_fn.m lines 96-100: EBE rate targets ----
inline constexpr double kEbeRg[6] = {
    32.7290, 32.1122, 30.3532, 33.6474, 64.1156, 66.8729};
inline constexpr double kEbeRd[21] = {
    7.5449, 10.7964, 10.9944, 11.0402, 11.7990, 15.3803, 42.6800, 41.4551,
    73.1939, 57.0430, 45.5920, 43.6553, 61.8002, 59.6409, 57.0279,
    51.0749, 67.1070, 60.6623, 198.6744, 178.9956, 199.9483};

} // namespace wpb_data

// ---- Shared helpers for the dispatch penalties ----
// Each helper implements one expression that recurs in the fn_* files. The
// order of operations matches the MATLAB code term for term.

// Round to 4 decimals. MATLAB round() and std::round both round ties away
// from zero.
inline double round4(double v) {
    return std::round(v * 10000.0) / 10000.0;
}

// Copy of x rounded to 4 decimals, as in the MY_FUNCTION_* wrappers:
// x = round(x*10000)/10000.
inline Vector round4_copy(std::span<const Real> x) {
    Vector r(x.size());
    for (std::size_t i = 0; i < x.size(); ++i) {
        r[i] = round4(x[i]);
    }
    return r;
}

inline double sum(std::span<const double> v) {
    double s = 0.0;
    for (const double value : v) {
        s += value;
    }
    return s;
}

// Limit-violation penalty used by every fn_* file:
//   sum(abs(v-lo)-(v-lo)) + sum(abs(hi-v)-(hi-v))
// This equals 2*sum(max(lo-v,0)) + 2*sum(max(v-hi,0)). The factor 2 comes
// from the reference. As in MATLAB, the two sums are kept separate and added
// last.
inline double limit_violation_sum(std::span<const double> v, std::span<const double> lo,
                                  std::span<const double> hi) {
    double low = 0.0;
    double high = 0.0;
    for (std::size_t i = 0; i < v.size(); ++i) {
        const double dl = v[i] - lo[i];
        low += std::abs(dl) - dl;
        const double dh = hi[i] - v[i];
        high += std::abs(dh) - dh;
    }
    return low + high;
}

// Prohibited operating zone (POZ) limits, stored like the reference
// POZ_Lower_Limits/POZ_Upper_Limits: rows = zones, columns = units.
struct PozZones {
    std::vector<Vector> lo;
    std::vector<Vector> hi;
    bool empty() const {
        return lo.empty();
    }
};

// POZ penalty: how far each unit output lies inside a zone.
//   sum(sum((POZ_lo<x & x<POZ_hi).*min(x-POZ_lo,POZ_hi-x)))
// The inside test is strict. As in MATLAB, it sums over the zones of each
// unit first, then over units. Zones with lo == hi and all-zero zones add 0.
inline double poz_penalty(std::span<const double> x, const PozZones& z) {
    double total = 0.0;
    for (std::size_t u = 0; u < x.size(); ++u) {
        double per_unit = 0.0;
        for (std::size_t zi = 0; zi < z.lo.size(); ++zi) {
            const double lo = z.lo[zi][u];
            const double hi = z.hi[zi][u];
            if (lo < x[u] && x[u] < hi) {
                per_unit += std::min(x[u] - lo, hi - x[u]);
            }
        }
        total += per_unit;
    }
    return total;
}

// Power_Loss = (x*B1*x') + (B2*x') + B3, in MATLAB evaluation order:
// y = x*B1 with y(j) = sum_k x(k)*B1(k,j), then y*x', then + B2*x' + B3.
// An empty b1 or b2 means an all-zero matrix, as in fn_ELD_13/40/140 and
// fn_DED_10, where the loss is exactly 0.
inline double transmission_loss(std::span<const double> x, const std::vector<Vector>& b1,
                                std::span<const double> b2, double b3) {
    double quad = 0.0;
    if (!b1.empty()) {
        for (std::size_t j = 0; j < x.size(); ++j) {
            double yj = 0.0;
            for (std::size_t k = 0; k < x.size(); ++k) {
                yj += x[k] * b1[k][j];
            }
            quad += yj * x[j];
        }
    }
    double lin = 0.0;
    for (std::size_t j = 0; j < b2.size(); ++j) {
        lin += b2[j] * x[j];
    }
    return quad + lin + b3;
}

// Production cost: sum(a.*x.^2 + b.*x + c [+ abs(e.*sin(f.*(Pmin-x)))]).
// Empty e/f means no valve-point term (fn_ELD_6/15).
inline double production_cost(std::span<const double> x, std::span<const double> a,
                              std::span<const double> b, std::span<const double> c,
                              std::span<const double> e, std::span<const double> f,
                              std::span<const double> pmin) {
    double total = 0.0;
    for (std::size_t i = 0; i < x.size(); ++i) {
        double term = (a[i] * (x[i] * x[i]) + b[i] * x[i]) + c[i];
        if (!e.empty()) {
            term += std::abs(e[i] * std::sin(f[i] * (pmin[i] - x[i])));
        }
        total += term;
    }
    return total;
}

template <std::size_t R, std::size_t C>
Vector column(const double (&table)[R][C], std::size_t c) {
    Vector v(R);
    for (std::size_t r = 0; r < R; ++r) {
        v[r] = table[r][c];
    }
    return v;
}

template <std::size_t R, std::size_t C>
std::vector<Vector> matrix(const double (&table)[R][C], double scale = 1.0) {
    std::vector<Vector> m(R, Vector(C));
    for (std::size_t r = 0; r < R; ++r) {
        for (std::size_t c = 0; c < C; ++c) {
            m[r][c] = table[r][c] * scale;
        }
    }
    return m;
}

inline Vector scaled(Vector v, double scale) {
    for (double& value : v) {
        value *= scale;
    }
    return v;
}

// Build POZ zones from consecutive (lo, hi) column pairs of a Data2-style
// table, like Prohibited_Operating_Zones_POZ = Data2(:,4:end)'.
// first_col is 0-based (3 = MATLAB column 4).
template <std::size_t R, std::size_t C>
PozZones poz_from_columns(const double (&table)[R][C], std::size_t first_col, std::size_t zones) {
    PozZones z;
    for (std::size_t zi = 0; zi < zones; ++zi) {
        z.lo.push_back(column(table, first_col + 2 * zi));
        z.hi.push_back(column(table, first_col + 2 * zi + 1));
    }
    return z;
}

inline Vector tile(std::span<const double> base, std::size_t copies) {
    Vector v;
    v.reserve(base.size() * copies);
    for (std::size_t r = 0; r < copies; ++r) {
        v.insert(v.end(), base.begin(), base.end());
    }
    return v;
}

// Dense matrix inverse by Gauss-Jordan elimination with partial pivoting.
// MATLAB inv() uses LAPACK LU (dgetrf/dgetri). On the well-conditioned
// 29x29 reduced susceptance matrix of problem 9 the two agree far inside the
// 1e-12 relative tolerance that the probe tests check.
// Throws std::runtime_error if a pivot is exactly 0.
std::vector<Vector> invert_dense(std::vector<Vector> a) {
    const std::size_t n = a.size();
    std::vector<Vector> inv(n, Vector(n, 0.0));
    for (std::size_t i = 0; i < n; ++i) {
        inv[i][i] = 1.0;
    }
    for (std::size_t col = 0; col < n; ++col) {
        std::size_t pivot = col;
        for (std::size_t r = col + 1; r < n; ++r) {
            if (std::abs(a[r][col]) > std::abs(a[pivot][col])) {
                pivot = r;
            }
        }
        if (a[pivot][col] == 0.0) {
            throw std::runtime_error("cec2011 f9: singular susceptance matrix.");
        }
        std::swap(a[pivot], a[col]);
        std::swap(inv[pivot], inv[col]);
        const double diag = a[col][col];
        for (std::size_t c = 0; c < n; ++c) {
            a[col][c] /= diag;
            inv[col][c] /= diag;
        }
        for (std::size_t r = 0; r < n; ++r) {
            if (r == col || a[r][col] == 0.0) {
                continue;
            }
            const double factor = a[r][col];
            for (std::size_t c = 0; c < n; ++c) {
                a[r][c] -= factor * a[col][c];
                inv[r][c] -= factor * inv[col][c];
            }
        }
    }
    return inv;
}

// ---- Common base class ----

// Base for all problems in this file: stores the id and bounds, checks the
// input size (throws std::invalid_argument) and applies the reference
// NaN -> 0 rule.
class WpbProblem : public BenchmarkProblem {
public:
    std::string suite_name() const override {
        return "cec2011";
    }
    int function_id() const override {
        return id_;
    }
    int dimension() const override {
        return static_cast<int>(lower_.size());
    }
    Bounds bounds() const override {
        return Bounds(lower_, upper_);
    }
    // CEC2011 real-world problems have no certified optimum: returns NaN.
    Real optimum() const override {
        return std::numeric_limits<Real>::quiet_NaN();
    }
    Real evaluate(std::span<const Real> x) const final {
        if (x.size() != lower_.size()) {
            throw std::invalid_argument("cec2011 f" + std::to_string(id_) +
                                        ": expected dimension " + std::to_string(lower_.size()) +
                                        ", got " + std::to_string(x.size()) + ".");
        }
        // As in Calc_Fitx_2011.m lines 57-61: NaN -> 0 on every evaluation.
        return apply_reference_nan_rule(evaluate_objective(x));
    }

protected:
    WpbProblem(int id, Vector lower, Vector upper)
        : id_(id), lower_(std::move(lower)), upper_(std::move(upper)),
          round4_scratch_(lower_.size()) {}

    virtual Real evaluate_objective(std::span<const Real> x) const = 0;

    // MY_FUNCTION_* 4-decimal rounding into a reused per-instance buffer, so
    // no allocation per call. evaluate() has already checked that
    // raw.size() == lower_.size(), so the buffer has the right size.
    // Gives the same values as round4_copy, bit for bit.
    std::span<const double> round4_into_scratch(std::span<const Real> raw) const {
        for (std::size_t i = 0; i < raw.size(); ++i) {
            round4_scratch_[i] = round4(raw[i]);
        }
        return round4_scratch_;
    }

private:
    int id_;
    Vector lower_;
    Vector upper_;
    mutable Vector round4_scratch_;
};

// ---- Problem 9: EBE transmission pricing, IEEE 30-bus (cost_fn.m) ----

class EbeTransmissionPricingProblem final : public WpbProblem {
public:
    EbeTransmissionPricingProblem() : EbeTransmissionPricingProblem(build()) {}

private:
    static constexpr std::size_t kBuses = 30;
    static constexpr std::size_t kLines = 41;
    static constexpr std::size_t kGens = 6;   // buses 1,2,5,8,11,13 (1-based)
    static constexpr std::size_t kLoads = 21; // buses with Pd > 0

    struct Model {
        Vector lower;
        Vector upper;
        Vector pg;                  // Pg at the 6 generators (cost_fn: Pg(g))
        Vector pd;                  // Pd at the 21 loads
        std::vector<Vector> bt;     // BT: 6x21 bilateral transactions
        Vector pg_net;              // pg - sum(BT,2)
        Vector pd_net;              // pd - sum(BT,1)'
        std::vector<std::size_t> na; // line from-bus (0-based)
        std::vector<std::size_t> nb; // line to-bus (0-based)
        Vector ptdf;                // PTDF, 6*21*41, index (i*21+j)*41+k
        Vector fc;                  // FC: 41 line facility costs
    };

    explicit EbeTransmissionPricingProblem(Model m)
        : WpbProblem(9, m.lower, m.upper), m_(std::move(m)) {}

    static Model build() {
        Model m;

        // Pg = bus_spec(:,7)/100, Pd = bus_spec(:,5)/100, g = find(Pg>0),
        // d = find(Pd>0). The reduced vectors keep the bus order.
        std::vector<std::size_t> g;
        std::vector<std::size_t> d;
        Vector pg_full(kBuses);
        Vector pd_full(kBuses);
        for (std::size_t bus = 0; bus < kBuses; ++bus) {
            pg_full[bus] = wpb_data::kEbeBusSpec[bus][6] / 100.0;
            pd_full[bus] = wpb_data::kEbeBusSpec[bus][4] / 100.0;
            if (pg_full[bus] > 0.0) {
                g.push_back(bus);
            }
            if (pd_full[bus] > 0.0) {
                d.push_back(bus);
            }
        }
        if (g.size() != kGens || d.size() != kLoads) {
            throw std::runtime_error("cec2011 f9: unexpected generator/load count.");
        }
        m.pg.resize(kGens);
        m.pd.resize(kLoads);
        for (std::size_t i = 0; i < kGens; ++i) {
            m.pg[i] = pg_full[g[i]];
        }
        for (std::size_t j = 0; j < kLoads; ++j) {
            m.pd[j] = pd_full[d[j]];
        }

        // Bilateral transactions BT, 50 MW in total (cost_fn.m lines 29-35,
        // same as define_boundaries.m case 9). Indices are 0-based positions
        // in the g/d lists, not bus numbers. The table is then divided by 100.
        m.bt.assign(kGens, Vector(kLoads, 0.0));
        m.bt[0][3] = 5.0;
        m.bt[0][4] = 10.0;
        m.bt[0][5] = 5.0;
        m.bt[1][2] = 5.0;
        m.bt[2][20] = 2.5;
        m.bt[3][20] = 2.5;
        m.bt[3][15] = 15.0;
        m.bt[4][11] = 2.5;
        m.bt[5][7] = 2.5;
        for (auto& row : m.bt) {
            for (double& value : row) {
                value /= 100.0;
            }
        }

        // Bounds are computed from the data (define_boundaries.m case 9):
        // xmin = 0, xmax = min(Pg(g(i))-BT(i,j), Pd(d(j))-BT(i,j)),
        // flattened with j fastest: x[i*21+j].
        m.lower.assign(kGens * kLoads, 0.0);
        m.upper.resize(kGens * kLoads);
        for (std::size_t i = 0; i < kGens; ++i) {
            for (std::size_t j = 0; j < kLoads; ++j) {
                m.upper[i * kLoads + j] =
                    std::min(m.pg[i] - m.bt[i][j], m.pd[j] - m.bt[i][j]);
            }
        }

        // Power left after the bilateral transactions (pg, pd in cost_fn.m):
        // pg_net = Pg - sum(BT,2), pd_net = Pd - sum(BT,1)'.
        m.pg_net.resize(kGens);
        for (std::size_t i = 0; i < kGens; ++i) {
            m.pg_net[i] = m.pg[i] - sum(m.bt[i]);
        }
        m.pd_net.resize(kLoads);
        for (std::size_t j = 0; j < kLoads; ++j) {
            double bt_col = 0.0;
            for (std::size_t i = 0; i < kGens; ++i) {
                bt_col += m.bt[i][j];
            }
            m.pd_net[j] = m.pd[j] - bt_col;
        }

        // Imaginary part of Ybus, as in EBEformybus.m. Only imag(Z) of each
        // line impedance is used: YI = 1./imag(Z).
        m.na.resize(kLines);
        m.nb.resize(kLines);
        Vector xij(kLines);
        std::vector<Vector> yibus(kBuses, Vector(kBuses, 0.0));
        for (std::size_t k = 0; k < kLines; ++k) {
            m.na[k] = static_cast<std::size_t>(wpb_data::kEbeLineData[k][0]) - 1;
            m.nb[k] = static_cast<std::size_t>(wpb_data::kEbeLineData[k][1]) - 1;
            const std::complex<double> z(wpb_data::kEbeLineData[k][2],
                                         wpb_data::kEbeLineData[k][3]);
            xij[k] = z.imag();
            const double yi = 1.0 / z.imag();
            const std::size_t a = m.na[k];
            const std::size_t b = m.nb[k];
            yibus[a][a] += yi;
            yibus[a][b] = -yi + yibus[a][b];
            yibus[b][a] = -yi + yibus[b][a];
            yibus[b][b] += yi;
        }

        // As in cost_fn.m: drop row 1 and column 1, invert, then add back a
        // zero first row and column (X(i+1,j+1) = Xt(i,j) for i,j >= 1).
        std::vector<Vector> reduced(kBuses - 1, Vector(kBuses - 1));
        for (std::size_t r = 1; r < kBuses; ++r) {
            for (std::size_t c = 1; c < kBuses; ++c) {
                reduced[r - 1][c - 1] = yibus[r][c];
            }
        }
        const std::vector<Vector> xt = invert_dense(std::move(reduced));
        std::vector<Vector> x(kBuses, Vector(kBuses, 0.0));
        for (std::size_t r = 1; r < kBuses; ++r) {
            for (std::size_t c = 1; c < kBuses; ++c) {
                x[r][c] = xt[r - 1][c - 1];
            }
        }

        // PTDF(i,j,k) = (X(na,g_i)-X(nb,g_i)-X(na,d_j)+X(nb,d_j))/xij(k).
        m.ptdf.resize(kGens * kLoads * kLines);
        for (std::size_t i = 0; i < kGens; ++i) {
            for (std::size_t j = 0; j < kLoads; ++j) {
                for (std::size_t k = 0; k < kLines; ++k) {
                    m.ptdf[(i * kLoads + j) * kLines + k] =
                        (x[m.na[k]][g[i]] - x[m.nb[k]][g[i]] - x[m.na[k]][d[j]] +
                         x[m.nb[k]][d[j]]) /
                        xij[k];
                }
            }
        }

        // FC = 100*xij/sum(xij).
        const double xij_total = sum(xij);
        m.fc.resize(kLines);
        for (std::size_t k = 0; k < kLines; ++k) {
            m.fc[k] = 100.0 * xij[k] / xij_total;
        }
        return m;
    }

    // Main body of cost_fn.m. This problem does not round x to 4 decimals.
    Real evaluate_objective(std::span<const Real> x) const override {
        constexpr double kKp = 100.0;

        // GD(i,:) = x((i-1)*21+1 : i*21), so gd(i,j) = x[i*21+j] (0-based).
        const auto gd = [&](std::size_t i, std::size_t j) {
            return x[i * kLoads + j];
        };
        const auto ptdf = [&](std::size_t i, std::size_t j, std::size_t k) {
            return m_.ptdf[(i * kLoads + j) * kLines + k];
        };

        // flows(k) = sum_ij |PTDF*GD| + |PTDF*BT|; cost_line = FC/flows.
        Vector cost_line(kLines);
        for (std::size_t k = 0; k < kLines; ++k) {
            double flow = 0.0;
            for (std::size_t i = 0; i < kGens; ++i) {
                for (std::size_t j = 0; j < kLoads; ++j) {
                    flow = flow + std::abs(ptdf(i, j, k) * gd(i, j)) +
                           std::abs(ptdf(i, j, k) * m_.bt[i][j]);
                }
            }
            cost_line[k] = m_.fc[k] / flow;
        }

        // cost_l(i,j) = sum_k |cost_line(k)*PTDF(i,j,k)|;
        // cost_gen(i) = sum_j GD(i,j)*cost_l(i,j);
        // rate_ebe1 = sum_i (cost_gen(i)/pg_net(i) - Rg(i))^2.
        std::vector<Vector> cost_l(kGens, Vector(kLoads, 0.0));
        double rate_ebe1 = 0.0;
        for (std::size_t i = 0; i < kGens; ++i) {
            double cost_gen = 0.0;
            for (std::size_t j = 0; j < kLoads; ++j) {
                for (std::size_t k = 0; k < kLines; ++k) {
                    cost_l[i][j] = cost_l[i][j] + std::abs(cost_line[k] * ptdf(i, j, k));
                }
                cost_gen = cost_gen + gd(i, j) * cost_l[i][j];
            }
            const double dev = cost_gen / m_.pg_net[i] - wpb_data::kEbeRg[i];
            rate_ebe1 = rate_ebe1 + dev * dev;
        }

        // cost_load(j) = sum_i GD(i,j)*cost_l(i,j);
        // rate_ebe2 = sum_j (cost_load(j)/pd_net(j) - Rd(j))^2.
        double rate_ebe2 = 0.0;
        for (std::size_t j = 0; j < kLoads; ++j) {
            double cost_load = 0.0;
            for (std::size_t i = 0; i < kGens; ++i) {
                cost_load = cost_load + gd(i, j) * cost_l[i][j];
            }
            const double dev = cost_load / m_.pd_net[j] - wpb_data::kEbeRd[j];
            rate_ebe2 = rate_ebe2 + dev * dev;
        }
        const double rate_d = rate_ebe1 + rate_ebe2;

        // Constraint penalties, each term weighted by 100: |Pg_x - Pg| with
        // Pg_x = sum(GD,2)+sum(BT,2), and |Pd_x - Pd| with
        // Pd_x = sum(GD,1)+sum(BT,1). Pg, Pd are the reduced m_.pg, m_.pd.
        double gpen = 0.0;
        for (std::size_t i = 0; i < kGens; ++i) {
            double gd_row = 0.0;
            for (std::size_t j = 0; j < kLoads; ++j) {
                gd_row += gd(i, j);
            }
            const double pg_x = gd_row + sum(m_.bt[i]);
            gpen = gpen + 100.0 * std::abs(pg_x - m_.pg[i]);
        }
        double ldpen = 0.0;
        for (std::size_t j = 0; j < kLoads; ++j) {
            double gd_col = 0.0;
            for (std::size_t i = 0; i < kGens; ++i) {
                gd_col += gd(i, j);
            }
            double bt_col = 0.0;
            for (std::size_t i = 0; i < kGens; ++i) {
                bt_col += m_.bt[i][j];
            }
            const double pd_x = gd_col + bt_col;
            ldpen = ldpen + 100.0 * std::abs(pd_x - m_.pd[j]);
        }
        const double penalty = gpen + ldpen;

        return rate_d + 50.0 * kKp * penalty;
    }

    Model m_;
};

// ---- Problems 11-12: dynamic economic dispatch, DED (fn_DED_5/10.m) ----

class DynamicEconomicDispatchProblem final : public WpbProblem {
public:
    struct Config {
        int id = 0;
        std::size_t units = 0;
        Vector demand; // one value per hour (24)
        Vector pmin, pmax, a, b, c, e, f;
        Vector up_ramp, down_ramp;
        PozZones poz;            // empty for fn_DED_10 (no POZ columns)
        std::vector<Vector> b1;  // empty = all-zero loss matrix
        bool round_loss = false; // [PRESERVE] only fn_DED_5 rounds Power_Loss
        double ramp_weight = 0.0; // [PRESERVE] 1e5 in fn_DED_5, 1e3 in fn_DED_10
    };

    explicit DynamicEconomicDispatchProblem(Config cfg)
        : WpbProblem(cfg.id, tile(cfg.pmin, kHours), tile(cfg.pmax, kHours)),
          cfg_(std::move(cfg)) {}

private:
    static constexpr std::size_t kHours = 24;

    Real evaluate_objective(std::span<const Real> raw) const override {
        const std::span<const double> x = round4_into_scratch(raw); // MY_FUNCTION_10_* rounding

        // Input_Generations = reshape(x,units,24)': hour j (0-based) is the
        // contiguous slice x[j*units .. j*units+units-1].
        const std::size_t units = cfg_.units;
        double total_cost = 0.0;
        double total_penalty = 0.0;
        Vector up(units);
        Vector down(units);
        std::span<const double> previous; // generations of hour j-1
        for (std::size_t j = 0; j < kHours; ++j) {
            const std::span<const double> xj{x.data() + j * units, units};

            double power_loss = transmission_loss(xj, cfg_.b1, {}, 0.0);
            if (cfg_.round_loss) {
                power_loss = round4(power_loss);
            }
            const double balance =
                std::abs(cfg_.demand[j] + power_loss - sum(xj));
            const double capacity = limit_violation_sum(xj, cfg_.pmin, cfg_.pmax);

            // Ramp limits link each hour to the one before. The first hour is
            // skipped, so the NaN initial Previous_Generations is never used.
            double ramp = 0.0;
            if (j > 0) {
                for (std::size_t u = 0; u < units; ++u) {
                    up[u] = std::min(cfg_.pmax[u], previous[u] + cfg_.up_ramp[u]);
                    down[u] = std::max(cfg_.pmin[u], previous[u] - cfg_.down_ramp[u]);
                }
                ramp = limit_violation_sum(xj, down, up);
            }
            previous = xj;

            const double poz = cfg_.poz.empty() ? 0.0 : poz_penalty(xj, cfg_.poz);
            total_cost += production_cost(xj, cfg_.a, cfg_.b, cfg_.c, cfg_.e, cfg_.f,
                                          cfg_.pmin);
            total_penalty +=
                ((1e3 * balance + 1e3 * capacity) + cfg_.ramp_weight * ramp) + 1e5 * poz;
        }
        return total_cost + total_penalty;
    }

    Config cfg_;
};

DynamicEconomicDispatchProblem::Config make_ded5_config() {
    using namespace wpb_data;
    DynamicEconomicDispatchProblem::Config cfg;
    cfg.id = 11;
    cfg.units = 5;
    cfg.demand.assign(std::begin(kDed5Demand), std::end(kDed5Demand));
    cfg.pmin = column(kDed5Data1, 0);
    cfg.pmax = column(kDed5Data1, 1);
    cfg.a = column(kDed5Data1, 2);
    cfg.b = column(kDed5Data1, 3);
    cfg.c = column(kDed5Data1, 4);
    cfg.e = column(kDed5Data1, 5);
    cfg.f = column(kDed5Data1, 6);
    cfg.up_ramp = column(kDed5Data2, 1);
    cfg.down_ramp = column(kDed5Data2, 2);
    // Both zones have lo == hi, so the POZ penalty is always 0. Kept because
    // the reference computes it.
    cfg.poz = poz_from_columns(kDed5Data2, 3, 2);
    cfg.b1 = matrix(kDed5B1);
    cfg.round_loss = true;
    cfg.ramp_weight = 1e5;
    return cfg;
}

DynamicEconomicDispatchProblem::Config make_ded10_config() {
    using namespace wpb_data;
    DynamicEconomicDispatchProblem::Config cfg;
    cfg.id = 12;
    cfg.units = 10;
    cfg.demand.assign(std::begin(kDed10Demand), std::end(kDed10Demand));
    cfg.pmin = column(kDed10Data1, 0); // unit 10 has Pmin==Pmax==55
    cfg.pmax = column(kDed10Data1, 1);
    cfg.a = column(kDed10Data1, 2);
    cfg.b = column(kDed10Data1, 3);
    cfg.c = column(kDed10Data1, 4);
    cfg.e = column(kDed10Data1, 5);
    cfg.f = column(kDed10Data1, 6);
    cfg.up_ramp = column(kDed10Data2, 1);
    cfg.down_ramp = column(kDed10Data2, 2);
    // Data2 has no POZ columns, so poz stays empty. B1 = B2 = B3 = 0, and
    // fn_DED_10 does not round the loss [PRESERVE].
    cfg.round_loss = false;
    cfg.ramp_weight = 1e3; // [PRESERVE] 1e3 here vs 1e5 in fn_DED_5
    return cfg;
}

// ---- Problems 13-16: static ELD (fn_ELD_6/13/15/40.m) ----
// ELD = economic load dispatch.

class StaticEldProblem final : public WpbProblem {
public:
    struct Config {
        int id = 0;
        double demand = 0.0;
        Vector pmin, pmax, a, b, c;
        Vector e, f;              // empty = no valve-point term
        Vector up_limit, down_limit; // empty = no ramp or POZ terms (Data2=[])
        PozZones poz;
        std::vector<Vector> b1;   // empty = all-zero loss matrix
        Vector b2;
        double b3 = 0.0;
        double balance_weight = 0.0;  // [PRESERVE] 1e3 (6/15) vs 1e5 (13/40)
    };

    explicit StaticEldProblem(Config cfg)
        : WpbProblem(cfg.id, cfg.pmin, cfg.pmax), cfg_(std::move(cfg)) {}

private:
    Real evaluate_objective(std::span<const Real> raw) const override {
        const std::span<const double> x = round4_into_scratch(raw); // MY_FUNCTION_11_* rounding

        double power_loss = transmission_loss(x, cfg_.b1, cfg_.b2, cfg_.b3);
        power_loss = round4(power_loss);
        const double balance = std::abs(cfg_.demand + power_loss - sum(x));
        const double capacity = limit_violation_sum(x, cfg_.pmin, cfg_.pmax);

        double total_penalty;
        if (!cfg_.up_limit.empty()) {
            // fn_ELD_6/15: fixed ramp limits from Po (set once, not linked
            // across hours), plus POZ.
            const double ramp = limit_violation_sum(x, cfg_.down_limit, cfg_.up_limit);
            const double poz = poz_penalty(x, cfg_.poz);
            total_penalty = ((cfg_.balance_weight * balance + 1e3 * capacity) +
                             1e5 * ramp) +
                            1e5 * poz;
        } else {
            // fn_ELD_13/40: no ramp, no POZ.
            total_penalty = cfg_.balance_weight * balance + 1e3 * capacity;
        }
        const double cost =
            production_cost(x, cfg_.a, cfg_.b, cfg_.c, cfg_.e, cfg_.f, cfg_.pmin);
        return cost + total_penalty;
    }

    Config cfg_;
};

// Fixed ramp limits: Up_Ramp_Limit = min(Pmax,Po+UR),
// Down_Ramp_Limit = max(Pmin,Po-DR). Set cfg.pmin and cfg.pmax first.
void set_static_ramp_limits(StaticEldProblem::Config& cfg, const Vector& po,
                            const Vector& ur, const Vector& dr) {
    const std::size_t n = po.size();
    cfg.up_limit.resize(n);
    cfg.down_limit.resize(n);
    for (std::size_t i = 0; i < n; ++i) {
        cfg.up_limit[i] = std::min(cfg.pmax[i], po[i] + ur[i]);
        cfg.down_limit[i] = std::max(cfg.pmin[i], po[i] - dr[i]);
    }
}

StaticEldProblem::Config make_eld6_config() {
    using namespace wpb_data;
    StaticEldProblem::Config cfg;
    cfg.id = 13;
    cfg.demand = 1263.0;
    cfg.pmin = column(kEld6Data1, 0);
    cfg.pmax = column(kEld6Data1, 1);
    cfg.a = column(kEld6Data1, 2);
    cfg.b = column(kEld6Data1, 3);
    cfg.c = column(kEld6Data1, 4); // quadratic cost only, no valve point
    set_static_ramp_limits(cfg, column(kEld6Data2, 0), column(kEld6Data2, 1),
                           column(kEld6Data2, 2));
    cfg.poz = poz_from_columns(kEld6Data2, 3, 2);
    // [PRESERVE] The reference B1 is not symmetric: (6,1) = +0.2 but
    // (1,6) = -0.2 (a typo), and (5,3) = -0.1 but (3,5) = -1.0.
    cfg.b1 = matrix(kEld6B1Raw, 1e-5);
    cfg.b2 = scaled(Vector(std::begin(kEld6B2Raw), std::end(kEld6B2Raw)), 1e-5);
    cfg.b3 = 0.0056 * 1e-2;
    cfg.balance_weight = 1e3;
    return cfg;
}

StaticEldProblem::Config make_eld13_config() {
    using namespace wpb_data;
    StaticEldProblem::Config cfg;
    cfg.id = 14;
    cfg.demand = 1800.0;
    cfg.pmin = column(kEld13Data1, 0);
    cfg.pmax = column(kEld13Data1, 1);
    cfg.a = column(kEld13Data1, 2);
    cfg.b = column(kEld13Data1, 3);
    cfg.c = column(kEld13Data1, 4);
    cfg.e = column(kEld13Data1, 5);
    cfg.f = column(kEld13Data1, 6);
    cfg.balance_weight = 1e5; // [PRESERVE] 1e5 here vs 1e3 in fn_ELD_6/15
    return cfg;
}

StaticEldProblem::Config make_eld15_config() {
    using namespace wpb_data;
    StaticEldProblem::Config cfg;
    cfg.id = 15;
    cfg.demand = 2630.0;
    cfg.pmin = column(kEld15Data1, 0);
    cfg.pmax = column(kEld15Data1, 1);
    cfg.a = column(kEld15Data1, 2);
    cfg.b = column(kEld15Data1, 3);
    cfg.c = column(kEld15Data1, 4); // quadratic cost only, no valve point
    set_static_ramp_limits(cfg, column(kEld15Data2, 0), column(kEld15Data2, 1),
                           column(kEld15Data2, 2));
    cfg.poz = poz_from_columns(kEld15Data2, 3, 3);
    cfg.b1 = matrix(kEld15B1Raw, 1e-5);
    cfg.b2 = scaled(Vector(std::begin(kEld15B2Raw), std::end(kEld15B2Raw)), 1e-5);
    cfg.b3 = 0.0055 * 1e-2;
    cfg.balance_weight = 1e3;
    return cfg;
}

StaticEldProblem::Config make_eld40_config() {
    using namespace wpb_data;
    StaticEldProblem::Config cfg;
    cfg.id = 16;
    cfg.demand = 10500.0;
    cfg.pmin = column(kEld40Data1, 0);
    cfg.pmax = column(kEld40Data1, 1);
    cfg.a = column(kEld40Data1, 2);
    cfg.b = column(kEld40Data1, 3);
    cfg.c = column(kEld40Data1, 4);
    cfg.e = column(kEld40Data1, 5);
    cfg.f = column(kEld40Data1, 6);
    cfg.balance_weight = 1e5;
    return cfg;
}

// ---- Problem 17: static ELD, 140 units, Korean grid (fn_ELD_140.m) ----
// Separate from StaticEldProblem because its penalties are summed in a
// different way (a vector broadcast quirk and 1e7 weights).

class Eld140Problem final : public WpbProblem {
public:
    Eld140Problem() : Eld140Problem(build()) {}

private:
    static constexpr std::size_t kUnits = 140;

    struct Model {
        Vector pmin, pmax, a, b, c, e, f;
        Vector up_limit, down_limit;
        PozZones poz;
    };

    explicit Eld140Problem(Model m)
        : WpbProblem(17, m.pmin, m.pmax), m_(std::move(m)) {}

    static Model build() {
        using namespace wpb_data;
        Model m;
        m.pmin = column(kEld140Data1, 0);
        m.pmax = column(kEld140Data1, 1);
        // [PRESERVE] Data1 columns are [Pmin Pmax c b a]: the cost
        // coefficients are in reverse order compared with the other ELD files.
        m.c = column(kEld140Data1, 2);
        m.b = column(kEld140Data1, 3);
        m.a = column(kEld140Data1, 4);

        // Data1(Data3(:,1),6:7) = Data3(:,2:3) sets valve-point coefficients
        // for 12 units only. MATLAB grows the matrix and fills the rest with 0.
        m.e.assign(kUnits, 0.0);
        m.f.assign(kUnits, 0.0);
        for (const auto& row : kEld140Data3) {
            const std::size_t unit = static_cast<std::size_t>(row[0]) - 1;
            m.e[unit] = row[1];
            m.f[unit] = row[2];
        }

        // Fixed ramp limits from Data2 = [Po UR DR].
        const Vector po = column(kEld140Data2, 0);
        const Vector ur = column(kEld140Data2, 1);
        const Vector dr = column(kEld140Data2, 2);
        m.up_limit.resize(kUnits);
        m.down_limit.resize(kUnits);
        for (std::size_t i = 0; i < kUnits; ++i) {
            m.up_limit[i] = std::min(m.pmax[i], po[i] + ur[i]);
            m.down_limit[i] = std::max(m.pmin[i], po[i] - dr[i]);
        }

        // Data2(Data4(:,1),4:9) = Data4(:,2:end): three POZ zones for units
        // 8, 32, 74 and 136 (1-based). All other units get zones (0,0), which
        // never pass the strict inside test.
        m.poz.lo.assign(3, Vector(kUnits, 0.0));
        m.poz.hi.assign(3, Vector(kUnits, 0.0));
        for (const auto& row : kEld140Data4) {
            const std::size_t unit = static_cast<std::size_t>(row[0]) - 1;
            for (std::size_t zi = 0; zi < 3; ++zi) {
                m.poz.lo[zi][unit] = row[1 + 2 * zi];
                m.poz.hi[zi][unit] = row[2 + 2 * zi];
            }
        }
        return m;
    }

    Real evaluate_objective(std::span<const Real> raw) const override {
        const std::span<const double> x = round4_into_scratch(raw); // MY_FUNCTION_11_5 rounding
        constexpr double kDemand = 49342.0;

        // B1 = B2 = B3 = 0; the loss is still computed and rounded (it is 0).
        double power_loss = transmission_loss(x, {}, {}, 0.0);
        power_loss = round4(power_loss);
        const double balance = std::abs(kDemand + power_loss - sum(x));

        // [PRESERVE] fn_ELD_140.m line 354 has no sum() around the
        // lower-bound term:
        //   Capacity_Limits_Penalty = (abs(x-Pmin)-(x-Pmin))
        //                           + sum(abs(Pmax-x)-(Pmax-x));
        // MATLAB adds the scalar upper-bound sum to each of the 140 elements,
        // and the weight line then sums the vector, so the upper-bound
        // violation is counted 140 times.
        double upper_violation = 0.0;
        for (std::size_t i = 0; i < kUnits; ++i) {
            const double dh = m_.pmax[i] - x[i];
            upper_violation += std::abs(dh) - dh;
        }
        double capacity = 0.0;
        for (std::size_t i = 0; i < kUnits; ++i) {
            const double dl = x[i] - m_.pmin[i];
            capacity += (std::abs(dl) - dl) + upper_violation;
        }

        // The ramp penalty is also a 140-vector, summed in the weight line:
        // the sum over units of the (low + high) terms.
        double ramp = 0.0;
        for (std::size_t i = 0; i < kUnits; ++i) {
            const double dl = x[i] - m_.down_limit[i];
            const double dh = m_.up_limit[i] - x[i];
            ramp += (std::abs(dl) - dl) + (std::abs(dh) - dh);
        }

        const double poz = poz_penalty(x, m_.poz);

        // [PRESERVE] Weights differ from the other ELD files:
        // 1e7*PB + 1e5*sum(Cap) + 1e7*sum(Ramp) + 1e5*POZ.
        const double total_penalty =
            ((1e7 * balance + 1e5 * capacity) + 1e7 * ramp) + 1e5 * poz;
        const double cost = production_cost(x, m_.a, m_.b, m_.c, m_.e, m_.f, m_.pmin);
        return cost + total_penalty;
    }

    Model m_;
};

// ---- Problems 18-20: hydrothermal scheduling (fn_HT_ELD_Case_1/2/3.m) ----
// One class for all three cases. They differ only in the POZ term:
//   case 1 (P18): no POZ;
//   case 2 (P19): POZ on the discharges, weight 1e5;
//   case 3 (P20): POZ computed but weighted 0, so results equal case 1
//                 [PRESERVE].

class HydrothermalSchedulingProblem final : public WpbProblem {
public:
    enum class Case { one, two, three };

    HydrothermalSchedulingProblem(int id, Case variant)
        : WpbProblem(id, tile(kQmin, kHours), tile(kQmax, kHours)), variant_(variant) {}

private:
    static constexpr std::size_t kPlants = 4;
    static constexpr std::size_t kHours = 24;
    // Constants from fn_HT_ELD_Case_*.m lines 27-45.
    static constexpr double kPtMin = 500.0;
    static constexpr double kPtMax = 2500.0;
    static constexpr double kPhMin[kPlants] = {0, 0, 0, 0};
    static constexpr double kPhMax[kPlants] = {500, 500, 500, 500};
    static constexpr int kDelayTime[kPlants] = {2, 3, 4, 0};
    static constexpr int kNoOfUpstreams[kPlants] = {0, 0, 2, 1};
    static constexpr double kVmin[kPlants] = {80, 60, 100, 70};
    static constexpr double kVmax[kPlants] = {150, 120, 240, 160};
    static constexpr double kVInitial[kPlants] = {100, 80, 170, 120};
    static constexpr double kVFinal[kPlants] = {120, 70, 170, 140};
    static constexpr double kQmin[kPlants] = {5, 6, 10, 13};
    static constexpr double kQmax[kPlants] = {15, 15, 30, 25};
    // Case 2/3 POZ zones on the discharges, one zone per plant.
    static constexpr double kPozLo[kPlants] = {8, 7, 22, 16};
    static constexpr double kPozHi[kPlants] = {9, 8, 27, 18};

    Real evaluate_objective(std::span<const Real> raw) const override {
        const std::span<const double> x = round4_into_scratch(raw); // MY_FUNCTION_12_* rounding

        // Input_Discharges = reshape(x,4,24), no transpose: column j is
        // hour j, so q(plant i, hour j) = x[j*4+i] (0-based).
        const auto q = [&](std::size_t plant, std::size_t hour) {
            return x[hour * kPlants + plant];
        };

        // Reservoir cascade: plant 3 receives the discharge of plants 1 and
        // 2; plant 4 receives plant 3. Upstream water arrives after the
        // upstream plant's delay (kDelayTime). All_Discharges = [zeros(4,4) Q]
        // gives 4 columns of zero history. All_Spillages and Spillages are
        // always zero, so those terms are left out (exact no-ops).
        // Storage_Volume(i,j+1) = V(i,j) + Upstream - Q(i,j) + Inflow(i,j).
        double volume[kPlants][kHours + 1];
        for (std::size_t i = 0; i < kPlants; ++i) {
            volume[i][0] = kVInitial[i];
        }
        for (std::size_t i = 0; i < kPlants; ++i) {
            for (std::size_t j = 0; j < kHours; ++j) {
                double upstream = 0.0;
                for (int k = static_cast<int>(i) - kNoOfUpstreams[i];
                     k < static_cast<int>(i); ++k) {
                    const auto plant = static_cast<std::size_t>(k);
                    const int hour = static_cast<int>(j) - kDelayTime[plant];
                    upstream += hour >= 0 ? q(plant, static_cast<std::size_t>(hour)) : 0.0;
                }
                volume[i][j + 1] = ((volume[i][j] + upstream) - q(i, j)) +
                                   wpb_data::kHtInflowRate[i][j];
            }
        }

        double total_cost = 0.0;
        double total_penalty = 0.0;
        for (std::size_t j = 0; j < kHours; ++j) {
            double qj[kPlants];
            double vj[kPlants];
            for (std::size_t i = 0; i < kPlants; ++i) {
                qj[i] = q(i, j);
                vj[i] = volume[i][j + 1];
            }
            const double discharge = limit_violation_sum(qj, kQmin, kQmax);
            const double storage = limit_violation_sum(vj, kVmin, kVmax);

            // Ph = c1*v^2 + c2*q^2 + c3*v*q + c4*v + c5*q + c6, then
            // Ph.*(Ph>0): negative hydro generation becomes 0 [PRESERVE].
            double ph[kPlants];
            for (std::size_t i = 0; i < kPlants; ++i) {
                const double* cc = wpb_data::kHtCCoefficients[i];
                const double generation =
                    ((((cc[0] * (vj[i] * vj[i]) + cc[1] * (qj[i] * qj[i])) +
                       cc[2] * (vj[i] * qj[i])) +
                      cc[3] * vj[i]) +
                     cc[4] * qj[i]) +
                    cc[5];
                ph[i] = generation > 0.0 ? generation : 0.0;
            }
            const double hydro_capacity = limit_violation_sum(ph, kPhMin, kPhMax);

            // Power_Loss is always 0 in all three cases.
            const double hydro_total = sum(ph);
            const double p_thermal = wpb_data::kHtDemand[j] - hydro_total;

            // [PRESERVE] The reference computes the thermal capacity penalty
            // but never adds it to All_Penalty. Kept here, unused, to show
            // the dropped term.
            const double dtl = p_thermal - kPtMin;
            const double dth = kPtMax - p_thermal;
            const double thermal_capacity =
                (std::abs(dtl) - dtl) + (std::abs(dth) - dth);
            (void)thermal_capacity;

            // The power-balance penalty recomputes the thermal residual, so
            // it is always exactly 0 [PRESERVE].
            const double balance =
                std::abs((wpb_data::kHtDemand[j] - hydro_total) - p_thermal);

            double poz = 0.0;
            if (variant_ != Case::one) {
                double per_plant[kPlants];
                for (std::size_t i = 0; i < kPlants; ++i) {
                    per_plant[i] = (kPozLo[i] < qj[i] && qj[i] < kPozHi[i])
                                       ? std::min(qj[i] - kPozLo[i], kPozHi[i] - qj[i])
                                       : 0.0;
                }
                poz = sum(per_plant);
            }

            // Thermal cost. All three case files comment out the valve-point
            // term, although the case 3 header mentions valve-point loading
            // [PRESERVE].
            total_cost +=
                (5000.0 + 19.2 * p_thermal) + 0.002 * (p_thermal * p_thermal);

            // [PRESERVE] All three cases add the hydro capacity penalty
            // twice. The POZ weight is 1e5 in case 2 and 0 in case 3; case 1
            // has no POZ term.
            double hour_penalty = (((1e4 * balance + 1e4 * hydro_capacity) +
                                    1e4 * hydro_capacity) +
                                   1e4 * discharge) +
                                  1e5 * storage;
            if (variant_ == Case::two) {
                hour_penalty = hour_penalty + 1e5 * poz;
            } else if (variant_ == Case::three) {
                hour_penalty = hour_penalty + 0.0 * poz;
            }
            total_penalty += hour_penalty;
        }

        // Reservoir end-volume penalty. The first term compares V(:,1) with
        // V_Initial and is always 0 [PRESERVE].
        double end_initial = 0.0;
        double end_final = 0.0;
        for (std::size_t i = 0; i < kPlants; ++i) {
            end_initial += std::abs(volume[i][0] - kVInitial[i]);
        }
        for (std::size_t i = 0; i < kPlants; ++i) {
            end_final += std::abs(volume[i][kHours] - kVFinal[i]);
        }
        const double reservoir_end = end_initial + end_final;

        return total_cost + (total_penalty + 1e6 * reservoir_end);
    }

    Case variant_;
};

} // namespace

std::unique_ptr<BenchmarkProblem> make_problem_wpb(int function_id,
                                                   const std::filesystem::path& /*data_root*/) {
    // All data tables are built into this file (the reference keeps them
    // inside its .m files), so data_root is not used. Any id other than 9
    // or 11-20 throws std::invalid_argument.
    switch (function_id) {
    case 9:
        return std::make_unique<EbeTransmissionPricingProblem>();
    case 11:
        return std::make_unique<DynamicEconomicDispatchProblem>(make_ded5_config());
    case 12:
        return std::make_unique<DynamicEconomicDispatchProblem>(make_ded10_config());
    case 13:
        return std::make_unique<StaticEldProblem>(make_eld6_config());
    case 14:
        return std::make_unique<StaticEldProblem>(make_eld13_config());
    case 15:
        return std::make_unique<StaticEldProblem>(make_eld15_config());
    case 16:
        return std::make_unique<StaticEldProblem>(make_eld40_config());
    case 17:
        return std::make_unique<Eld140Problem>();
    case 18:
        return std::make_unique<HydrothermalSchedulingProblem>(
            18, HydrothermalSchedulingProblem::Case::one);
    case 19:
        return std::make_unique<HydrothermalSchedulingProblem>(
            19, HydrothermalSchedulingProblem::Case::two);
    case 20:
        return std::make_unique<HydrothermalSchedulingProblem>(
            20, HydrothermalSchedulingProblem::Case::three);
    default:
        throw std::invalid_argument(
            "cec2011 work package B implements only function ids 9 and 11..20, got " +
            std::to_string(function_id) + ".");
    }
}

} // namespace gskcec::cec2011::detail
