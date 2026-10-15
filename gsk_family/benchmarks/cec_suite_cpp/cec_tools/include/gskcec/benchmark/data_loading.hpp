#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>

namespace gskcec {

/// Reads every whitespace-separated number in a text file.
///
/// Used for CEC input data: shift vectors, rotation matrices and shuffle
/// indices. Throws std::runtime_error naming the file when it is missing,
/// unreadable, empty, or holds a non-numeric token.
Vector load_values_file(const std::filesystem::path& path);

/// Like load_values_file, but returns only the first @p expected_count values.
///
/// Throws std::runtime_error naming the file, the expected count and the
/// actual count when the file holds fewer values. Extra values are ignored,
/// as in the reference CEC readers, which fscanf only the first n values
/// (the CEC2013 shift_data and CEC2017/CEC2020 M_/shuffle loaders need this).
Vector load_values_file(const std::filesystem::path& path, std::size_t expected_count);

/// Throws std::runtime_error naming @p path when the file does not exist.
void require_file(const std::filesystem::path& path);

} // namespace gskcec
