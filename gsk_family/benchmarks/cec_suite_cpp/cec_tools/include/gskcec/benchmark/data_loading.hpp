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

/// Same as load_values_file, but additionally verifies the value count.
///
/// Throws std::runtime_error naming the file path, the expected count and
/// the actual count on mismatch.
Vector load_values_file(const std::filesystem::path& path, std::size_t expected_count);

/// Throws std::runtime_error naming @p path when it does not exist.
void require_file(const std::filesystem::path& path);

} // namespace gskcec
