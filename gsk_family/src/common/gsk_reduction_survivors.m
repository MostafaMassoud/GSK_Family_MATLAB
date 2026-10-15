function survivors = gsk_reduction_survivors(fitness, num_remove)
%GSK_REDUCTION_SURVIVORS Indices kept by linear population reduction.
%
%   survivors = gsk_reduction_survivors(fitness, num_remove)
%
% Returns the row indices (column vector, in original row order) that
% survive after removing the num_remove worst individuals by current
% fitness.
%
% Reference behavior transcribed from the population resizing loop in:
%   historical source: agsk/agsk/AGSK-CODE-FINAL/Adaptive_GSK_ALI.m
%   historical source: apgsk/apgsk/APGSK Code/Adaptive_GSK_ALI.m
%     for r = 1 : reduction_ind_num
%         [valBest indBest] = sort(fitness, 'ascend');
%         worst_ind = indBest(end);
%         popold(worst_ind,:) = []; pop(worst_ind,:) = [];
%         fitness(worst_ind,:) = []; K(worst_ind,:) = [];
%     end
%
% Equivalence: MATLAB sort is stable, so sequentially deleting the
% last-ranked row removes exactly the last num_remove entries of the
% initial stable ascending ordering (ties on the worst value are removed
% from the highest original row index downwards, exactly as the reference
% loop does), and row deletion preserves the relative order of survivors.
% Consumes no random numbers.

np = numel(fitness);
[~, indBest] = sort(fitness(:), 'ascend');
survivors = sort(indBest(1:np - num_remove));
survivors = survivors(:);

end
