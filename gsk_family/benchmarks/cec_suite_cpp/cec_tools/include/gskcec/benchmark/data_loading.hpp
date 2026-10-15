#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>

namespace gskcec {

/// Loads all whitespace-separated floating point values from a text file.
///
/// Used for CEC input data such as shift vectors, rotation matrices and
/// shuffle index files. Throws std::runtime_error naming the file path when
/// the file is missing, unreadable, or contains a non-numeric token.
Vector load_values_file(const std::filesystem::path& path);

/// Same as load_values_file, but returns only the first @p expected_count values.
///
/// Throws std::runtime_error naming the file path, the expected count and
/// the actual count when the file holds fewer than @p expected_count values.
/// Extra values beyond @p expected_count are ignored (not an error); this
/// matches the reference CEC readers, which fscanf only the first n values
/// (the cec2013 shift_data and cec2017/cec2020 M_/shuffle loaders rely on it).
Vector load_values_file(const std::filesystem::path& path, std::size_t expected_count);

/// Throws std::runtime_error naming @p path when it does not exist.
void require_file(const std::filesystem::path& path);

} // namespace gskcec
