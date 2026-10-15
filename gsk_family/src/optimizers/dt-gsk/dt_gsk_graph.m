classdef dt_gsk_graph < handle
%DT_GSK_GRAPH Interaction graph of DT-GSK (success-graph structural memory, SGSM).
%
% Used by the D >= 50 tiers. The graph learns which dimensions improve together:
% every accepted move (trial - parent) adds the outer product of its normalised
% |displacement|, weighted by its fitness improvement, to a symmetric D x D
% co-improvement matrix, and all accumulators decay a little every generation.
% Periodically the graph is cut into blocks of co-adapting dimensions, each with
% a confidence score. Once the blocks are mature and confident enough, they
% replace the random linkage groups of the blockwise junior/senior masks. The
% eigenvectors of the signed co-movement matrix give the directions for the
% final polish.
%
% Reference: DT-GSK v2.46, https://github.com/MostafaMassoud/DT-GSK; Masoud,
% Roshdy, Mohamed, Algorithms (MDPI), 2026.
% Bit-exact with the reference: sums whose bits matter use np_sum (NumPy pairwise
% summation) or explicit left-to-right loops, and ties are broken by stable sorts.
% Dimension indices are 1-based.
%
% Scope: only what the pub profile uses is implemented. The trailing generation
% argument of extract_blocks and absolute-minimum argument of adaptive_threshold
% are accepted for interface compatibility and ignored (the latter is 0 in every
% pub tier).

    properties (SetAccess = private)
        matrix                      % D x D co-improvement weights (symmetric, >= 0, zero diagonal)
        signed_matrix               % D x D signed co-movement weights (symmetric, zero diagonal)
        support                     % D x D weighted pair-support counts (symmetric, zero diagonal)
        blocks = cell(1, 0)         % learned blocks: sorted 1-based index rows, ordered by first dim
        overall_confidence = 0      % size-weighted block confidence x sqrt(coverage)
        nontrivial_dims = 0         % number of dims covered by blocks
        updates = 0                 % accepted moves absorbed so far
        refresh_count = 0           % block extractions so far
        confidence_history = zeros(1, 0)   % overall_confidence after each refresh (last 256)
    end

    methods
        function G = dt_gsk_graph(D)
            G.matrix = zeros(D);
            G.signed_matrix = zeros(D);
            G.support = zeros(D);
        end

        function update(G, X, imp, decay, lr, sw)
            % Decay all accumulators, then absorb the accepted moves X (n x D)
            % with improvements imp (> 0). sw holds per-move weights ([] = 1);
            % a weight of 0 drops the move (e.g. DE offspring).
            G.matrix = G.matrix * decay;
            G.signed_matrix = G.signed_matrix * decay;
            G.support = G.support * decay;
            n = size(X, 1);
            if n == 0 || isempty(imp), return; end
            if isempty(sw), sw = ones(n, 1); end
            D = size(X, 2);
            agg = zeros(D); agg_s = zeros(D); agg_n = zeros(D);
            used = 0;
            A = abs(X);
            for i = 1:n
                s = sw(i);
                if ~(imp(i) > 0 && imp(i) < Inf && s > 0 && s < Inf), continue; end
                idx = find(A(i, :) > 1e-15);              % dims the move touched
                if isempty(idx), continue; end
                denom = np_sum(A(i, idx));
                if ~(denom > 1e-15 && denom < Inf), continue; end
                w = imp(i) * s;
                va = A(i, idx) / denom;                   % |move| as a distribution
                vs = X(i, idx) / denom;                   % signed counterpart
                % Rank-1 updates on the touched block (diagonals are discarded below).
                agg(idx, idx) = agg(idx, idx) + w * (va.' .* va);
                agg_s(idx, idx) = agg_s(idx, idx) + w * (vs.' .* vs);
                agg_n(idx, idx) = agg_n(idx, idx) + s;
                used = used + 1;
            end
            if used > 0 && lr > 0
                G.matrix = symmetrise(G.matrix + lr * agg, true);
                G.signed_matrix = symmetrise(G.signed_matrix + lr * agg_s, false);
                G.support = symmetrise(G.support + agg_n, true);
                G.updates = G.updates + used;
            end
        end

        function extract_blocks(G, edge_floor, min_b, max_b, ~)
            % Re-cut the graph into blocks and score their confidence.
            D = size(G.matrix, 1);
            prev = G.blocks;
            % Normalised graph (max edge 1); an empty graph gives no blocks.
            W = symmetrise(G.matrix, true);
            mx = max(W(:), [], 'includenan');
            groups = cell(1, 0);
            if mx > 0 && mx < Inf
                W = W / mx;
                % Neighbour graph: each dim links to its strongest edges (at least
                % half its row maximum and at least edge_floor; if none qualify,
                % any positive edge), at most max_b - 1 of them, ties -> lower index.
                rmax = max(W, [], 2);
                cand = W >= max(0.5 * rmax, edge_floor) & rmax > 0;
                none = ~any(cand, 2);
                cand(none, :) = W(none, :) > 0;
                key = -W;
                key(~cand) = Inf;
                [~, ord] = sort(key, 2);                   % stable: strongest first
                k = min(max_b - 1, D);
                pick = (1:k) <= sum(cand, 2);              % D x k: the first k candidates
                rows = repmat((1:D).', 1, k);
                cols = ord(:, 1:k);
                adj = false(D);
                adj(rows(pick) + (cols(pick) - 1) * D) = true;
                adj = adj | adj.';
                % Connected components, in order of their smallest dim; oversized
                % ones are split greedily.
                seen = false(1, D);
                for s = 1:D
                    if seen(s), continue; end
                    m = false(1, D); m(s) = true; f = m;
                    while any(f)
                        f = any(adj(f, :), 1) & ~m;
                        m = m | f;
                    end
                    seen = seen | m;
                    comp = find(m);
                    if numel(comp) <= max_b
                        groups{end + 1} = comp; %#ok<AGROW>
                    else
                        groups = [groups, split_component(W, comp, max_b - 1)]; %#ok<AGROW>
                    end
                end
                groups = groups(cellfun(@numel, groups) >= min_b);
            end
            % Blocks are disjoint, so ordering by first dim is a total order.
            if ~isempty(groups)
                [~, o] = sort(cellfun(@(b) b(1), groups));
                groups = groups(o);
            end
            % Block confidence = edge density x sqrt(raw signal x support signal)
            % x (0.5 + 0.5 x stability); the three means run over the block's
            % pairs, stability is the best Jaccard overlap with a previous block.
            prev_of = zeros(1, D);                         % previous block of each dim
            for p = 1:numel(prev), prev_of(prev{p}) = p; end
            prev_size = cellfun(@numel, prev);
            nb = numel(groups);
            conf = zeros(1, nb);
            for t = 1:nb
                b = groups{t};
                [r, c] = find(tril(true(numel(b)), -1));  % pairs c < r in NumPy's triu order
                e = b(c) + (b(r) - 1) * D;                 % linear index of entry (b(c), b(r))
                rel = np_sum(W(e)) / numel(e);
                raw = np_sum(G.matrix(e)) / numel(e);      % >= 0
                sup = np_sum(G.support(e)) / numel(e);     % >= 0
                in = prev_of(b);
                stab = 0;
                for p = in(in > 0)
                    inter = sum(in == p);
                    stab = max(stab, inter / (numel(b) + prev_size(p) - inter));
                end
                conf(t) = rel * sqrt((1 - exp(-raw)) * (1 - exp(-sup))) * (0.5 + 0.5 * stab);
            end
            sizes = cellfun(@numel, groups);
            G.blocks = groups;
            G.nontrivial_dims = sum(sizes);
            if nb > 0
                % Size-weighted mean confidence, discounted by the covered fraction.
                G.overall_confidence = np_sum(conf .* sizes) / sum(sizes) * sqrt(G.nontrivial_dims / D);
            else
                G.overall_confidence = 0;
            end
            G.refresh_count = G.refresh_count + 1;
            G.confidence_history = [G.confidence_history(max(1, end - 254):end), G.overall_confidence];
        end

        function groups = linkage_groups(G, D)
            % Learned blocks plus every uncovered dim as a singleton, ordered by first dim.
            covered = false(1, D);
            covered([G.blocks{:}]) = true;
            groups = [G.blocks, num2cell(find(~covered))];
            [~, o] = sort(cellfun(@(g) g(1), groups));
            groups = groups(o);
        end

        function tf = ready(G, conf_min, min_updates, min_refreshes, min_dims)
            % True once the blocks are mature and confident enough to use.
            tf = ~isempty(G.blocks) && G.updates >= min_updates && G.refresh_count >= min_refreshes ...
                && G.nontrivial_dims >= min_dims && G.overall_confidence >= conf_min;
        end

        function thr = adaptive_threshold(G, static_thr, q, floor_v, min_samples, window, ~)
            % Confidence gate: the q-quantile of the last `window` refresh
            % confidences, at least floor_v; static_thr until min_samples refreshes.
            h = G.confidence_history;
            n = numel(h);
            if n < max(1, min_samples)
                thr = static_thr;
                return;
            end
            if window > 0 && window < n, h = h(end - window + 1:end); end
            thr = max(floor_v, np_quantile(h, q));
        end

        function restart_decay(G, f)
            % Shrink the accumulated evidence after a population restart.
            G.matrix = G.matrix * f;
            G.signed_matrix = G.signed_matrix * f;
            G.support = G.support * f;
        end

        function [basis, src] = polish_basis(G, D)
            % Final-polish directions (one per row): eigenvectors of the signed
            % matrix by descending |eigenvalue| (stable, from numpy's ascending
            % order); coordinate axes when there is no signal. src names the choice.
            basis = eye(D);
            src = 'axes';
            S = G.signed_matrix;
            if any(S(:) ~= 0)
                [V, ev] = eig(0.5 * (S + S.'), 'vector');  % exactly symmetric input
                [ev, asc] = sort(ev);
                [~, o] = sort(-abs(ev));
                B = V(:, asc(o)).';
                if all(isfinite(B(:)))
                    basis = B;
                    src = 'sgsm_eig';
                end
            end
        end
    end
end

function M = symmetrise(M, nonneg)
% 0.5*(M + M'), optionally clamped at 0, with a zero diagonal.
M = 0.5 * (M + M.');
if nonneg, M(M < 0) = 0; end
M(1:size(M, 1) + 1:end) = 0;
end

function groups = split_component(W, comp, cap)
% Greedy split of an oversized component: the dim with the largest in-component
% weight seeds a group with its `cap` strongest partners; repeat on the rest.
groups = cell(1, 0);
while ~isempty(comp)
    S = W(comp, comp);
    rs = zeros(numel(comp), 1);
    for j = 1:numel(comp), rs = rs + S(:, j); end   % left-to-right row sums
    [~, k] = max(rs);                               % seed: first maximum
    others = [1:k - 1, k + 1:numel(comp)];
    [~, o] = sort(-S(k, others));                   % strongest first, ties -> lower index
    take = [k, others(o(1:min(cap, end)))];
    groups{end + 1} = sort(comp(take)); %#ok<AGROW>
    comp(take) = [];
end
end

function v = np_quantile(a, q)
% np.quantile(a, q), default 'linear' method, bit-exact.
a = sort(a);
n = numel(a);
h = q * (n - 1);
lo = floor(h);
t = h - lo;
x0 = a(lo + 1);
x1 = a(min(lo + 2, n));
d = x1 - x0;
if t >= 0.5
    v = x1 - d * (1 - t);
else
    v = x0 + d * t;
end
end

function s = np_sum(a)
% np.sum of a float64 vector, bit-exact: NumPy's pairwise summation
% (sequential below 8 values, 8 running partial sums up to 128, halving above).
n = numel(a);
if n < 8
    s = 0;
    for i = 1:n, s = s + a(i); end
elseif n <= 128
    m = n - mod(n, 8);
    r = a(1:8);
    for i = 9:8:m, r = r + a(i:i + 7); end
    s = ((r(1) + r(2)) + (r(3) + r(4))) + ((r(5) + r(6)) + (r(7) + r(8)));
    for i = m + 1:n, s = s + a(i); end
else
    h = floor(n / 2);
    h = h - mod(h, 8);
    s = np_sum(a(1:h)) + np_sum(a(h + 1:n));
end
end
