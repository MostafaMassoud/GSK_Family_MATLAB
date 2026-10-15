function survivors = gsk_reduction_survivors(fitness, num_remove)
%GSK_REDUCTION_SURVIVORS Indices kept by linear population reduction.
%
%   survivors = gsk_reduction_survivors(fitness, num_remove)
%
% Returns the row indices that survive after removing the num_remove worst
% individuals by current fitness, as a column vector in original row order.
% Draws no random numbers.
%
% Source: the population resizing loop in Adaptive_GSK_ALI.m
% (agsk/agsk/AGSK-CODE-FINAL/ and apgsk/apgsk/APGSK Code/):
%     for r = 1 : reduction_ind_num
%         [valBest indBest] = sort(fitness, 'ascend');
%         worst_ind = indBest(end);
%         popold(worst_ind,:) = []; pop(worst_ind,:) = [];
%         fitness(worst_ind,:) = []; K(worst_ind,:) = [];
%     end
%
% Why one sort is equivalent: MATLAB sort is stable, so deleting the
% last-ranked row num_remove times removes exactly the last num_remove
% entries of the initial ascending order. Ties on the worst value go from
% the highest original row index down, as in the reference loop, and row
% deletion keeps the survivors in their relative order.

np = numel(fitness);
[~, indBest] = sort(fitness(:), 'ascend');
survivors = sort(indBest(1:np - num_remove));
survivors = survivors(:);

end
